# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

module ZeroXDA
  module MarketBrokerBot
    class MarketAPI
      class Error < StandardError
        attr_reader :code

        def initialize(message, code: "market_api_error")
          @code = code
          super(message)
        end
      end

      def initialize(base_url:, operator_token:)
        raise ArgumentError, "Market operator token must not be empty" if operator_token.to_s.empty?

        @base_url = URI("#{base_url.delete_suffix("/")}/")
        @operator_token = operator_token
      end

      def authenticate_telegram(user:, chat:)
        document = post(
          "operator/v1/auth/telegram",
          telegram_user_id: user.fetch("id"),
          chat_id: chat.fetch("id"),
          username: user["username"],
          first_name: user["first_name"],
          last_name: user["last_name"],
          language_code: user["language_code"]
        )
        document.fetch("data")
      end

      def health
        uri = URI.join(@base_url, "health")
        request = Net::HTTP::Get.new(uri)
        perform(uri, request)
      end

      private

      def perform(uri, request)
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 5,
          read_timeout: 10
        ) { |http| http.request(request) }
        document = JSON.parse(response.body)
        return document if response.is_a?(Net::HTTPSuccess)

        failure = document.fetch("errors", [{}]).first
        raise Error.new(
          failure["message"] || "Market API request failed",
          code: failure["code"] || response.code
        )
      rescue Error
        raise
      rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error => error
        raise Error, "Market API request failed: #{error.message}"
      end

      def post(path, payload)
        uri = URI.join(@base_url, path)
        request = Net::HTTP::Post.new(uri)
        request["authorization"] = "Bearer #{@operator_token}"
        request["content-type"] = "application/json"
        request.body = JSON.generate(payload)
        perform(uri, request)
      end
    end
  end
end
