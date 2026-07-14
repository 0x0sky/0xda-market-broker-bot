# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

module ZeroXDA
  module MarketBrokerBot
    class MarketAPI
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 75
      MAX_REQUEST_ATTEMPTS = 6
      RETRYABLE_STATUS_CODES = %w[502 503 504].freeze
      RETRY_BACKOFF_SECONDS = [2, 4, 8, 16, 30].freeze
      TRANSIENT_ERRORS = [IOError, SystemCallError, Timeout::Error].freeze

      class RetryableResponseError < StandardError; end

      class Error < StandardError
        attr_reader :code

        def initialize(message, code: "market_api_error")
          @code = code
          super(message)
        end
      end

      def initialize(base_url:, operator_token:, sleeper: Kernel.method(:sleep))
        raise ArgumentError, "Market operator token must not be empty" if operator_token.to_s.empty?

        @base_url = URI("#{base_url.delete_suffix("/")}/")
        @operator_token = operator_token
        @sleeper = sleeper
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
        get("health", authenticated: false)
      end

      def products
        get("operator/v1/products", authenticated: true).fetch("data")
      end

      private

      def get(path, authenticated:)
        uri = URI.join(@base_url, path)
        request = Net::HTTP::Get.new(uri)
        request["authorization"] = "Bearer #{@operator_token}" if authenticated
        perform(uri, request)
      end

      def perform(uri, request)
        response, document = request_with_retry(uri, request)
        return document if response.is_a?(Net::HTTPSuccess)

        failure = document.fetch("errors", [{}]).first
        raise Error.new(
          failure["message"] || "Market API request failed",
          code: failure["code"] || response.code
        )
      rescue Error
        raise
      rescue RetryableResponseError, JSON::ParserError, IOError, SystemCallError, Timeout::Error => error
        raise Error, "Market API request failed: #{error.message}"
      end

      def request_with_retry(uri, request)
        attempts = 0

        begin
          attempts += 1
          response = perform_http_request(uri, request)
          raise RetryableResponseError, "temporary HTTP #{response.code}" if retryable_status?(response)

          document = parse_document(response)
          [response, document]
        rescue *TRANSIENT_ERRORS, RetryableResponseError, JSON::ParserError
          if attempts < MAX_REQUEST_ATTEMPTS
            @sleeper.call(RETRY_BACKOFF_SECONDS.fetch(attempts - 1))
            retry
          end

          raise
        end
      end

      def retryable_status?(response)
        RETRYABLE_STATUS_CODES.include?(response.code)
      end

      def parse_document(response)
        JSON.parse(response.body)
      rescue JSON::ParserError => error
        raise JSON::ParserError, "temporary non-JSON response (HTTP #{response.code}): #{error.message}"
      end

      def perform_http_request(uri, request)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        ) { |http| http.request(request) }
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
