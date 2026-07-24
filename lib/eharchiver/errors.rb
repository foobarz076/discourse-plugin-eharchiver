# frozen_string_literal: true

module Eharchiver
  class Error < StandardError
  end

  class ConfigurationError < Error
  end

  class PolicyDenied < Error
  end

  class ArtifactError < Error
  end

  class DaemonError < Error
    attr_reader :http_status, :response_code

    def initialize(message, http_status: nil, response_code: nil)
      super(message)
      @http_status = http_status
      @response_code = response_code
    end
  end
end
