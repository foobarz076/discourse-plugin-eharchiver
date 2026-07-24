# frozen_string_literal: true

module Eharchiver
  module GalleryUrl
    SUPPORTED_HOSTS = %w[e-hentai.org exhentai.org].freeze
    PATH_PATTERN = %r{\A/g/([1-9]\d*)/([0-9a-f]{10})/?\z}i

    def self.canonicalize(value)
      uri, match = parse(value)

      "https://#{uri.host.downcase}/g/#{match[1]}/#{match[2].downcase}/"
    end

    def self.identity(value)
      _uri, match = parse(value)

      [match[1].to_i, match[2].downcase].freeze
    end

    def self.same_identity?(left, right)
      identity(left) == identity(right)
    rescue Discourse::InvalidParameters
      false
    end

    def self.parse(value)
      uri = URI.parse(value.to_s)
      match = PATH_PATTERN.match(uri.path.to_s)
      valid_port = uri.port == 443
      if uri.scheme != "https" || SUPPORTED_HOSTS.exclude?(uri.host&.downcase) || !valid_port ||
           uri.userinfo.present? || uri.query.present? || uri.fragment.present? || match.nil?
        raise Discourse::InvalidParameters.new(:gallery_url)
      end

      [uri, match]
    rescue URI::Error
      raise Discourse::InvalidParameters.new(:gallery_url)
    end
    private_class_method :parse
  end
end
