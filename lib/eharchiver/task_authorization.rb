# frozen_string_literal: true

require "jwt"

module Eharchiver
  class TaskAuthorization
    AUDIENCE = "eharchiver-daemon"

    def self.issue(
      task_id:,
      user:,
      topic:,
      gallery_url:,
      quality:,
      max_cost_gp:,
      min_remaining_gp:,
      now: Time.now.utc
    )
      secret = SiteSetting.eharchiver_task_signing_secret
      if secret.blank? || secret.bytesize < 32
        raise ConfigurationError, "Task signing secret must contain at least 32 bytes."
      end

      issued_at = now.to_i
      payload = {
        "v" => 2,
        "jti" => task_id,
        "iss" => Discourse.base_url,
        "aud" => AUDIENCE,
        "sub" => user.id.to_s,
        "topic_id" => topic.id,
        "gallery_url" => GalleryUrl.canonicalize(gallery_url),
        "quality" => quality,
        "max_gp" => max_cost_gp,
        "min_gp_balance" => min_remaining_gp,
        "max_image_width" => SiteSetting.eharchiver_pdf_max_width,
        "jpeg_quality" => SiteSetting.eharchiver_jpeg_quality,
        "include_uploader_comment" => SiteSetting.eharchiver_include_uploader_comment,
        "iat" => issued_at,
        "exp" => issued_at + SiteSetting.eharchiver_task_token_ttl_seconds,
      }
      JWT.encode(payload, secret, "HS256", { typ: "JWT" })
    end
  end
end
