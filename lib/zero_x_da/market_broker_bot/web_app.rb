# frozen_string_literal: true

require "json"
require "rack"

module ZeroXDA
  module MarketBrokerBot
    class WebApp
      MAX_BODY_BYTES = 1_048_576
      JSON_HEADERS = {
        "content-type" => "application/json; charset=utf-8",
        "cache-control" => "no-store"
      }.freeze

      def initialize(bot:, webhook_secret:)
        raise ArgumentError, "Webhook secret must not be empty" if webhook_secret.to_s.empty?

        @bot = bot
        @webhook_secret = webhook_secret
      end

      def call(environment)
        request = Rack::Request.new(environment)
        if request.post? && request.path_info == "/telegram/webhook"
          return json_response(401, error: "unauthorized") unless authorized?(request)

          raw = request.body.read(MAX_BODY_BYTES + 1)
          return json_response(413, error: "payload_too_large") if raw.bytesize > MAX_BODY_BYTES

          @bot.handle(JSON.parse(raw))
          return json_response(200, status: "accepted")
        end

        json_response(404, error: "not_found")
      rescue JSON::ParserError
        json_response(400, error: "invalid_json")
      end

      private

      def authorized?(request)
        provided = request.get_header("HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN").to_s
        return false if provided.empty? || provided.bytesize != @webhook_secret.bytesize

        Rack::Utils.secure_compare(provided, @webhook_secret)
      end

      def json_response(status, document)
        [status, JSON_HEADERS, [JSON.generate(document)]]
      end
    end
  end
end
