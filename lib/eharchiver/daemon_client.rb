# frozen_string_literal: true

require "faraday"
require "json"
require "digest"

module Eharchiver
  class DaemonClient
    MAX_JSON_BYTES = 1024 * 1024

    def initialize(
      base_url: SiteSetting.eharchiver_daemon_url,
      api_key: SiteSetting.eharchiver_daemon_api_key
    )
      @base_url = validate_base_url(base_url)
      if api_key.blank? || api_key.bytesize < 32
        raise ConfigurationError, "Daemon API key must contain at least 32 bytes."
      end

      timeout = SiteSetting.eharchiver_daemon_request_timeout_seconds
      @connection =
        Faraday.new(
          url: @base_url,
          request: {
            timeout: timeout,
            open_timeout: timeout,
          },
        ) do |builder|
          builder.headers["Accept"] = "application/json"
          builder.headers["Content-Type"] = "application/json"
          builder.headers["X-EHArchiver-API-Key"] = api_key
          builder.adapter Faraday.default_adapter
        end
    end

    def submit(authorization)
      request(:post, "v1/tasks", authorization: authorization)
    end

    def task(task_id)
      request(:get, "v1/tasks/#{validate_task_id(task_id)}")
    end

    def cancel(task_id)
      request(:post, "v1/tasks/#{validate_task_id(task_id)}/cancel")
    end

    def download_artifact(task_id, destination, max_bytes:)
      digest = Digest::SHA256.new
      bytes = 0
      response =
        @connection.get("v1/tasks/#{validate_task_id(task_id)}/artifact") do |request|
          request.headers["Accept"] = "application/zip"
          request.options.on_data =
            lambda do |chunk, _overall_bytes, _env|
              bytes += chunk.bytesize
              if bytes > max_bytes
                raise DaemonError, "Daemon artifact exceeds the configured size limit."
              end

              digest.update(chunk)
              destination.write(chunk)
            end
        end
      if !response.success?
        raise DaemonError.new(
                "Daemon returned HTTP #{response.status} while downloading the artifact.",
                http_status: response.status,
              )
      end

      destination.flush
      { size_bytes: bytes, sha256: digest.hexdigest }
    rescue DaemonError
      raise
    rescue Faraday::Error => error
      raise DaemonError, "Unable to download the daemon artifact: #{error.message}"
    end

    private

    def request(method, path, payload = nil)
      response =
        @connection.public_send(method, path) do |request|
          request.body = JSON.generate(payload) if payload
        end
      body = response.body.to_s
      raise DaemonError, "Daemon response is too large." if body.bytesize > MAX_JSON_BYTES

      parsed = body.present? ? JSON.parse(body) : {}
      if !response.success?
        message = parsed.is_a?(Hash) ? parsed["detail"] : nil
        raise DaemonError.new(
                message.presence || "Daemon returned HTTP #{response.status}.",
                http_status: response.status,
                response_code: parsed.is_a?(Hash) ? parsed["code"] : nil,
              )
      end
      raise DaemonError, "Daemon returned a non-object response." if !parsed.is_a?(Hash)

      parsed
    rescue DaemonError
      raise
    rescue Faraday::Error, JSON::ParserError => error
      raise DaemonError, "Unable to communicate with the daemon: #{error.message}"
    end

    def validate_base_url(value)
      uri = URI.parse(value.to_s)
      if !%w[http https].include?(uri.scheme) || uri.host.blank? || uri.userinfo.present? ||
           uri.query.present? || uri.fragment.present?
        raise ConfigurationError, "Daemon URL must be an HTTP(S) origin or path."
      end
      uri.path = "#{uri.path.delete_suffix("/")}/"
      uri.to_s
    rescue URI::InvalidURIError
      raise ConfigurationError, "Daemon URL is invalid."
    end

    def validate_task_id(task_id)
      value = task_id.to_s
      raise Discourse::InvalidParameters.new(:task_id) if !/\A[0-9a-f-]{36}\z/.match?(value)

      value
    end
  end
end
