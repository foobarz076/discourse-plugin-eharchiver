# frozen_string_literal: true

require "openssl"

module Eharchiver
  class WebhooksController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    skip_before_action :check_xhr
    skip_before_action :verify_authenticity_token
    skip_before_action :redirect_to_login_if_required

    def task_status
      return head :forbidden if !valid_signature?

      payload = JSON.parse(request.raw_post)
      snapshot = payload["task"]
      return head :bad_request if !snapshot.is_a?(Hash)

      task = Task.find_by(task_id: snapshot["task_id"])
      task&.apply_daemon_snapshot!(snapshot)
      head :no_content
    rescue JSON::ParserError, DaemonError
      head :bad_request
    end

    private

    def valid_signature?
      secret = SiteSetting.eharchiver_webhook_signing_secret
      timestamp = Integer(request.headers["X-EHArchiver-Timestamp"], exception: false)
      supplied = request.headers["X-EHArchiver-Signature"].to_s
      return false if secret.blank? || timestamp.nil? || (Time.now.to_i - timestamp).abs > 300

      signed = "#{timestamp}.#{request.raw_post}"
      expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, signed)}"
      ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
    end
  end
end
