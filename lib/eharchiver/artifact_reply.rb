# frozen_string_literal: true

require "digest"
require "json"
require "tempfile"

module Eharchiver
  class ArtifactReply
    MANIFEST_SCHEMA_VERSION = 3
    MAX_MANIFEST_BYTES = 1024 * 1024
    MAX_MARKDOWN_BYTES = 2 * 1024 * 1024
    MAX_ENTRIES = 10_000
    MAX_COMPRESSION_RATIO = 20
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/
    IMAGE_PATH_PATTERN = %r{\Aimages/[0-9]{4,}\.jpg\z}
    PDF_NAME_PATTERN = /\A[0-9]+-[0-9a-f]{10}\.pdf\z/

    class << self
      def publish!(task)
        DistributedMutex.synchronize("eharchiver-finalize-#{task.task_id}") do
          task.reload
          return existing_reply(task) if task.reply_post_id.present?

          existing = reply_by_custom_field(task)
          if existing
            update_stored_topic_metadata!(task, existing)
            task.update!(reply_post: existing)
            return existing
          end

          download_and_publish(task)
        end
      end

      private

      def download_and_publish(task)
        max_bytes = SiteSetting.eharchiver_max_artifact_size_mb.megabytes
        Tempfile.create(["eharchiver-#{task.task_id}-", ".zip"]) do |package|
          package.binmode
          downloaded =
            DaemonClient.new.download_artifact(task.task_id, package, max_bytes: max_bytes)
          verify_package!(task, downloaded)
          package.rewind

          Compression::SafeZipReader.open(
            package.path,
            max_entries: MAX_ENTRIES,
            max_total_bytes: max_bytes,
            max_compression_ratio: MAX_COMPRESSION_RATIO,
          ) { |reader| publish_from_reader(task, reader) }
        end
      rescue Compression::SafeZipReader::Error, JSON::ParserError => error
        raise ArtifactError, "The daemon artifact is invalid: #{error.message}"
      end

      def publish_from_reader(task, reader)
        manifest_raw =
          reader.read_entry("artifact.json", max_bytes: MAX_MANIFEST_BYTES, required: true)
        manifest = JSON.parse(manifest_raw)
        files = validate_manifest!(task, reader, manifest)
        topic_title = topic_title_from(manifest)
        topic_tags = topic_tags_from(manifest)
        markdown =
          verified_string_entry(reader, files.fetch(:markdown), max_bytes: MAX_MARKDOWN_BYTES)
        uploads = files.fetch(:images).map { |file| upload_entry(reader, file, task) }
        pdf_file = files.fetch(:pdf)
        pdf_limit_bytes = SiteSetting.max_attachment_size_kb.kilobytes
        pdf_omitted = pdf_file.fetch(:size_bytes) > pdf_limit_bytes
        if pdf_omitted
          verify_entry(reader, pdf_file)
        else
          pdf_upload = upload_entry(reader, pdf_file, task)
        end
        raw = [markdown.rstrip, *uploads.map(&:to_markdown), pdf_upload&.to_markdown].compact.join(
          "\n\n",
        )

        source_post = task.source_post
        post =
          PostCreator.create!(
            BotUser.ensure!,
            topic_id: task.topic_id,
            reply_to_post_number: source_post&.post_number,
            raw: raw,
            skip_events: true,
            skip_guardian: true,
            skip_validations: true,
            custom_fields: {
              TRIGGER_SOURCE_POST_ID_FIELD => task.source_post_id,
              TASK_ID_POST_FIELD => task.task_id,
              ARTIFACT_TOPIC_TITLE_FIELD => topic_title,
              ARTIFACT_TOPIC_TAGS_FIELD => JSON.generate(topic_tags),
            }.compact,
          )
        if pdf_omitted
          FailureNotifier.pdf_omitted(
            task,
            reply_post: post,
            pdf_size_bytes: pdf_file.fetch(:size_bytes),
            limit_bytes: pdf_limit_bytes,
          )
        end
        update_topic_metadata!(task, title: topic_title, artifact_tags: topic_tags)
        task.update!(reply_post: post)
        post
      end

      def validate_manifest!(task, reader, manifest)
        raise ArtifactError, "Artifact manifest must be an object." if !manifest.is_a?(Hash)
        if manifest["schema_version"] != MANIFEST_SCHEMA_VERSION
          raise ArtifactError, "Artifact manifest schema is unsupported."
        end
        gallery = manifest["gallery"]
        if !gallery.is_a?(Hash) ||
             !GalleryUrl.same_identity?(gallery["source_url"], task.gallery_url)
          raise ArtifactError, "Artifact gallery does not match the task."
        end

        image_records = manifest.dig("images", "files")
        image_count = manifest.dig("images", "count")
        if !image_records.is_a?(Array) || image_records.empty? ||
             image_records.length != image_count
          raise ArtifactError, "Artifact image list is invalid."
        end
        images =
          image_records.map do |record|
            file_record(
              record,
              path: "images/#{record.is_a?(Hash) ? record["artifact"] : nil}",
              path_pattern: IMAGE_PATH_PATTERN,
            )
          end
        markdown =
          file_record(
            manifest["markdown"],
            path: manifest.dig("markdown", "file"),
            path_pattern: /\Areply\.md\z/,
          )
        pdf =
          file_record(
            manifest["pdf"],
            path: manifest.dig("pdf", "file"),
            path_pattern: PDF_NAME_PATTERN,
          )
        expected = [
          "artifact.json",
          markdown.fetch(:path),
          *images.map { |file| file.fetch(:path) },
          pdf.fetch(:path),
        ]
        actual = reader.entries.reject(&:directory?).map(&:name)
        if actual.uniq.length != actual.length || actual.to_set != expected.to_set
          raise ArtifactError, "Artifact package contents do not match its manifest."
        end

        { images: images, markdown: markdown, pdf: pdf }
      end

      def file_record(record, path:, path_pattern:)
        if !record.is_a?(Hash) || !path.is_a?(String) || !path_pattern.match?(path) ||
             path.include?("..") || path.start_with?("/")
          raise ArtifactError, "Artifact contains an unsafe file name."
        end
        size = Integer(record["size_bytes"], exception: false)
        sha256 = record["sha256"]
        if size.nil? || size <= 0 || !SHA256_PATTERN.match?(sha256.to_s)
          raise ArtifactError, "Artifact file metadata is invalid."
        end

        { path: path, name: File.basename(path), size_bytes: size, sha256: sha256 }
      end

      def verified_string_entry(reader, file, max_bytes:)
        data =
          reader.read_entry(
            file.fetch(:path),
            max_bytes: [file.fetch(:size_bytes), max_bytes].min,
            required: true,
          )
        verify_file_data!(file, data)
        data.force_encoding(Encoding::UTF_8)
        raise ArtifactError, "Artifact Markdown is not valid UTF-8." if !data.valid_encoding?

        data
      end

      def upload_entry(reader, file, task)
        with_verified_entry(reader, file) do |tempfile|
          upload = UploadCreator.new(tempfile, file.fetch(:name)).create_for(BotUser.ensure!.id)
          if upload.nil? || !upload.persisted? || upload.errors.present?
            message = upload&.errors&.full_messages&.join(", ").presence || "upload failed"
            raise ArtifactError, "Discourse rejected #{file.fetch(:name)}: #{message}"
          end

          return upload
        end
      end

      def verify_entry(reader, file)
        with_verified_entry(reader, file) { nil }
      end

      def with_verified_entry(reader, file)
        tempfile = Tempfile.new(["eharchiver-upload-", File.extname(file.fetch(:name))])
        tempfile.binmode
        reader.stream_entry_to_file(
          file.fetch(:path),
          tempfile,
          max_bytes: file.fetch(:size_bytes),
          required: true,
        )
        tempfile.flush
        tempfile.rewind
        verify_file_io!(file, tempfile)
        yield(tempfile)
      ensure
        tempfile&.close!
      end

      def verify_file_data!(file, data)
        if data.bytesize != file.fetch(:size_bytes) ||
             Digest::SHA256.hexdigest(data) != file.fetch(:sha256)
          raise ArtifactError, "Artifact file checksum does not match."
        end
      end

      def verify_file_io!(file, io)
        digest = Digest::SHA256.new
        size = 0
        while (chunk = io.read(1024 * 1024))
          size += chunk.bytesize
          digest.update(chunk)
        end
        if size != file.fetch(:size_bytes) || digest.hexdigest != file.fetch(:sha256)
          raise ArtifactError, "Artifact file checksum does not match."
        end
        io.rewind
      end

      def verify_package!(task, downloaded)
        if downloaded.fetch(:size_bytes) != task.artifact_size_bytes ||
             downloaded.fetch(:sha256) != task.artifact_sha256
          raise ArtifactError, "Downloaded artifact does not match the daemon task result."
        end
      end

      def topic_title_from(manifest)
        gallery = manifest.fetch("gallery")
        candidates =
          [gallery["japanese_title"], gallery["title"]].filter_map do |value|
            normalized = value.to_s.squish
            normalized.presence
          end
        title = candidates.first
        raise ArtifactError, "Artifact does not contain a usable topic title." if title.blank?

        title.truncate(SiteSetting.max_topic_title_length, omission: "")
      end

      def topic_tags_from(manifest)
        return [] if !SiteSetting.tagging_enabled

        grouped_tags = manifest.dig("gallery", "tags")
        raise ArtifactError, "Artifact contains an invalid trusted tag list." if
          !grouped_tags.is_a?(Hash)

        grouped_tags
          .flat_map do |namespace, values|
            raise ArtifactError, "Artifact contains an invalid trusted tag list." if
              !namespace.is_a?(String) || !values.is_a?(Array) ||
                values.any? { |value| !value.is_a?(String) }

            values.map { |value| DiscourseTagging.clean_tag("#{namespace}:#{value}") }
          end
          .compact_blank
          .uniq
          .first(SiteSetting.max_tags_per_topic)
      end

      def update_stored_topic_metadata!(task, post)
        title = post.custom_fields[ARTIFACT_TOPIC_TITLE_FIELD]
        tags_json = post.custom_fields[ARTIFACT_TOPIC_TAGS_FIELD]
        artifact_tags =
          if tags_json.present?
            parsed = JSON.parse(tags_json)
            raise ArtifactError, "Stored artifact tags are invalid." if
              !parsed.is_a?(Array) || parsed.any? { |tag| !tag.is_a?(String) }

            parsed
          else
            []
          end
        update_topic_metadata!(task, title: title, artifact_tags: artifact_tags)
      rescue JSON::ParserError => error
        raise ArtifactError, "Stored artifact tags are invalid: #{error.message}"
      end

      def update_topic_metadata!(task, title:, artifact_tags:)
        topic = task.topic.reload
        fields = {}
        fields[:title] = title if title.present? && topic.title != title
        desired_tags = desired_topic_tags(topic, artifact_tags)
        if desired_tags && topic.tags.pluck(:name).sort != desired_tags.sort
          fields[:tags] = desired_tags
        end
        return if fields.empty?

        first_post = topic.first_post
        revised =
          PostRevisor.new(first_post).revise!(
            Discourse.system_user,
            fields,
            bypass_bump: true,
            silent: true,
            skip_validations: true,
          )
        return if revised || topic_metadata_matches?(topic.reload, title, desired_tags)

        raise ArtifactError, "Discourse rejected the artifact topic metadata."
      end

      def desired_topic_tags(topic, artifact_tags)
        return if !SiteSetting.tagging_enabled

        (topic.tags.pluck(:name) + artifact_tags)
          .uniq
          .first(SiteSetting.max_tags_per_topic)
      end

      def topic_metadata_matches?(topic, title, desired_tags)
        title_matches = title.blank? || topic.title == title
        tags_match = desired_tags.nil? || topic.tags.pluck(:name).sort == desired_tags.sort
        title_matches && tags_match
      end

      def existing_reply(task)
        Post.find_by(id: task.reply_post_id)
      end

      def reply_by_custom_field(task)
        PostCustomField.find_by(name: TASK_ID_POST_FIELD, value: task.task_id)&.post
      end
    end
  end
end
