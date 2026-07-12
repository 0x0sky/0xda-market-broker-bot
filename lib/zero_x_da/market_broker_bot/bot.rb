# frozen_string_literal: true

require_relative "market_api"
require_relative "telegram_api"

module ZeroXDA
  module MarketBrokerBot
    class Bot
      START_COMMANDS = [
        { command: "start", description: "авторизація брокера" }
      ].freeze
      BROKER_COMMANDS = [
        { command: "start", description: "авторизація брокера" },
        { command: "ready", description: "приймати нові заявки" },
        { command: "pause", description: "призупинити заявки" },
        { command: "status", description: "поточний статус" }
      ].freeze

      def initialize(market_api:, telegram_api:, registry:)
        @market_api = market_api
        @telegram_api = telegram_api
        @registry = registry
      end

      def handle(update)
        message = update["message"]
        return unless private_message?(message)

        command = parse_command(message["text"])
        case command
        when "/start", "/ready"
          authenticate_and_set_status(message, "ready")
        when "/pause"
          authenticate_and_set_status(message, "paused")
        when "/status"
          show_status(message)
        end
      rescue KeyError, ArgumentError, MarketAPI::Error => error
        notify_failure(message, error)
      end

      private

      def authenticate_and_set_status(message, status)
        user = authenticate(message)
        broker = @registry.set_status(
          telegram_user_id: message.fetch("from").fetch("id"),
          chat_id: message.fetch("chat").fetch("id"),
          status: status
        )
        sync_commands(broker.chat_id)
        send_message(broker.chat_id, status_message(user, broker.status))
      end

      def show_status(message)
        user = authenticate(message)
        telegram_user_id = message.fetch("from").fetch("id")
        chat_id = message.fetch("chat").fetch("id")
        sync_commands(chat_id)
        send_message(chat_id, status_message(user, @registry.status(telegram_user_id)))
      end

      def authenticate(message)
        @market_api.authenticate_telegram(
          user: message.fetch("from"),
          chat: message.fetch("chat")
        )
      end

      def status_message(user, status)
        role = user.dig("attributes", "role")
        uuid = user.fetch("id")
        indicator = status == "ready" ? "🟢" : "⚪️"
        <<~TEXT.strip
          zeroxda-market · broker

          авторизація успішна ✅
          role: #{role}
          user: #{uuid[0, 8]}
          status: #{status} #{indicator}
        TEXT
      end

      def sync_commands(chat_id)
        @telegram_api.set_commands(
          BROKER_COMMANDS,
          scope: { type: "chat", chat_id: chat_id }
        )
      rescue TelegramAPI::Error => error
        warn "command menu sync failed: #{error.message}"
      end

      def parse_command(text)
        match = text.to_s.match(%r{\A(/\w+)(?:@\w+)?(?:\s|\z)})
        match&.[](1)&.downcase
      end

      def private_message?(message)
        message.is_a?(Hash) && message.dig("chat", "type") == "private"
      end

      def send_message(chat_id, text)
        @telegram_api.send_message(chat_id: chat_id, text: text)
      end

      def notify_failure(message, error)
        chat_id = message&.dig("chat", "id")
        return unless chat_id

        send_message(chat_id, "не вдалося виконати команду. спробуй ще раз.")
        warn "command failed: #{error.class}: #{error.message}"
      rescue TelegramAPI::Error
        nil
      end
    end
  end
end
