# frozen_string_literal: true

require "time"
require_relative "market_api"
require_relative "telegram_api"

module ZeroXDA
  module MarketBrokerBot
    class Bot
      SERVER_START_NOTICE = "сервер запускається…"
      SERVER_START_NOTICE_DELAY = 3
      START_COMMANDS = [
        { command: "start", description: "авторизація брокера" }
      ].freeze
      PAUSED_COMMANDS = [
        { command: "ready", description: "приймати нові заявки" },
        { command: "status", description: "поточний статус" }
      ].freeze
      READY_COMMANDS = [
        { command: "pause", description: "призупинити заявки" },
        { command: "status", description: "поточний статус" }
      ].freeze
      BUSY_COMMANDS = [
        { command: "status", description: "поточний статус" }
      ].freeze
      ADMIN_COMMANDS = [
        { command: "servers", description: "стан серверів" }
      ].freeze

      def initialize(
        market_api:,
        telegram_api:,
        registry:,
        clock: -> { Time.now.utc },
        server_start_notice_delay: SERVER_START_NOTICE_DELAY
      )
        @market_api = market_api
        @telegram_api = telegram_api
        @registry = registry
        @clock = clock
        @server_start_notice_delay = server_start_notice_delay
      end

      def handle(update)
        message = update["message"]
        return unless private_message?(message)

        command = parse_command(message["text"])
        if command
          with_server_start_notice(message) do
            case command
            when "/start", "/ready"
              authenticate_and_set_status(message, "ready")
            when "/pause"
              authenticate_and_set_status(message, "paused")
            when "/status"
              show_status(message)
            when "/servers"
              show_servers(message)
            end
          end
        end
      rescue KeyError, ArgumentError, MarketAPI::Error => error
        notify_failure(message, error)
      end

      private

      def with_server_start_notice(message)
        chat_id = message.fetch("chat").fetch("id")
        completed = false
        lock = Mutex.new
        notifier = Thread.new do
          sleep @server_start_notice_delay
          send_message(chat_id, SERVER_START_NOTICE) unless lock.synchronize { completed }
        rescue TelegramAPI::Error => error
          warn "server start notice failed: #{error.message}"
        end
        notifier.report_on_exception = false
        yield
      ensure
        if lock
          lock.synchronize { completed = true }
          notifier&.kill
        end
      end

      def authenticate_and_set_status(message, status)
        user = authenticate(message)
        telegram_user_id = message.fetch("from").fetch("id")
        chat_id = message.fetch("chat").fetch("id")
        current_status = @registry.status(telegram_user_id)
        if current_status == "busy"
          sync_commands(chat_id, current_status, user)
          send_message(chat_id, status_message(user, current_status))
          return
        end

        broker = @registry.set_status(
          telegram_user_id: telegram_user_id,
          chat_id: chat_id,
          status: status
        )
        sync_commands(broker.chat_id, broker.status, user)
        send_message(broker.chat_id, status_message(user, broker.status))
      end

      def show_status(message)
        user = authenticate(message)
        telegram_user_id = message.fetch("from").fetch("id")
        chat_id = message.fetch("chat").fetch("id")
        status = @registry.status(telegram_user_id)
        sync_commands(chat_id, status, user)
        send_message(chat_id, status_message(user, status))
      end

      def show_servers(message)
        user = authenticate(message)
        telegram_user_id = message.fetch("from").fetch("id")
        chat_id = message.fetch("chat").fetch("id")
        sync_commands(chat_id, @registry.status(telegram_user_id), user)
        return send_message(chat_id, "доступ заборонено.") unless admin?(user)

        health = @market_api.health
        core_status = health.fetch("status", "unknown")
        core_time = health.fetch("server_time", "—")
        text = <<~TEXT.strip
          zeroxda-market / servers

          market core: #{status_label(core_status)}
          core time: #{core_time}

          broker bot: ok ✅
          bot time: #{timestamp(@clock.call)}
        TEXT
        send_message(chat_id, text)
      end

      def authenticate(message)
        @market_api.authenticate_telegram(
          user: message.fetch("from"),
          chat: message.fetch("chat")
        )
      end

      def status_message(user, status)
        role = user.dig("attributes", "role")
        indicator = { "ready" => "🟢", "busy" => "🟠", "paused" => "⚪️" }.fetch(status)
        <<~TEXT.strip
          авторизація успішна ✅
          role: #{role}
          status: #{status} #{indicator}
        TEXT
      end

      def sync_commands(chat_id, status, user)
        @telegram_api.set_commands(
          commands_for(status, user),
          scope: { type: "chat", chat_id: chat_id }
        )
      rescue TelegramAPI::Error => error
        warn "command menu sync failed: #{error.message}"
      end

      def commands_for(status, user)
        commands = case status
                   when "paused" then PAUSED_COMMANDS
                   when "ready" then READY_COMMANDS
                   when "busy" then BUSY_COMMANDS
                   else raise ArgumentError, "broker status is invalid"
                   end
        admin?(user) ? [*commands, *ADMIN_COMMANDS] : commands
      end

      def admin?(user)
        user.dig("attributes", "role") == "admin"
      end

      def status_label(status)
        status == "ok" ? "ok ✅" : "#{status} ❌"
      end

      def timestamp(value)
        raise ArgumentError, "clock must return a Time" unless value.is_a?(Time)

        value.utc.iso8601(6)
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
