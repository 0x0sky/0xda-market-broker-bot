# frozen_string_literal: true

require "time"
require_relative "market_api"
require_relative "telegram_api"

module ZeroXDA
  module MarketBrokerBot
    class Bot
      SERVER_START_NOTICE = "0xda-market запускається…"
      SERVER_START_NOTICE_DELAY = 3
      STATUS_MESSAGE_TTL = 3
      CATALOG_PAGE_SIZE = 9
      CATALOG_COLUMNS = 3
      ADD_CALLBACK_PATTERN = /\Aadd_([a-z0-9][a-z0-9_-]{0,59})\z/
      LIST_COMMAND = { command: "list", description: "виставити продукт" }.freeze
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
        server_start_notice_delay: SERVER_START_NOTICE_DELAY,
        status_message_ttl: STATUS_MESSAGE_TTL
      )
        @market_api = market_api
        @telegram_api = telegram_api
        @registry = registry
        @clock = clock
        @server_start_notice_delay = server_start_notice_delay
        @status_message_ttl = status_message_ttl
      end

      def handle(update)
        message = update["message"]
        callback = update["callback_query"]
        return handle_callback(callback) if callback
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
            when "/list"
              show_products(message)
            when "/servers"
              show_servers(message)
            end
          end
        end
      rescue KeyError, ArgumentError, MarketAPI::Error => error
        notify_failure(message || callback&.fetch("message", nil), error)
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
          sync_commands(chat_id, current_status, user, authorized: true)
          send_status_message(chat_id, user, current_status)
          return
        end

        broker = @registry.set_status(
          telegram_user_id: telegram_user_id,
          chat_id: chat_id,
          status: status,
          role: user.dig("attributes", "role")
        )
        sync_commands(broker.chat_id, broker.status, user, authorized: broker.authorized)
        send_status_message(broker.chat_id, user, broker.status)
      end

      def show_status(message)
        telegram_user_id = message.fetch("from").fetch("id")
        chat_id = message.fetch("chat").fetch("id")
        broker = @registry.fetch(telegram_user_id, chat_id: chat_id)
        user = { "attributes" => { "role" => broker.role } }
        sync_commands(chat_id, broker.status, user, authorized: broker.authorized)
        send_status_message(chat_id, user, broker.status)
      end

      def show_products(message)
        user = authenticate(message)
        telegram_user_id = message.fetch("from").fetch("id")
        chat_id = message.fetch("chat").fetch("id")
        broker = remember_authorization(user, telegram_user_id: telegram_user_id, chat_id: chat_id)
        sync_commands(chat_id, broker.status, user, authorized: broker.authorized)
        send_message(
          chat_id,
          "обери продукт для виставлення:",
          reply_markup: catalog_keyboard(@market_api.products, callback_prefix: "add")
        )
      end

      def handle_callback(callback)
        match = ADD_CALLBACK_PATTERN.match(callback.fetch("data").to_s)
        return unless match

        message = callback.fetch("message")
        return unless private_message?(message)

        user = @market_api.authenticate_telegram(
          user: callback.fetch("from"),
          chat: message.fetch("chat")
        )
        telegram_user_id = callback.fetch("from").fetch("id")
        chat_id = message.fetch("chat").fetch("id")
        broker = remember_authorization(user, telegram_user_id: telegram_user_id, chat_id: chat_id)
        sync_commands(chat_id, broker.status, user, authorized: broker.authorized)
        product = @market_api.products.find { |entry| entry.fetch("id") == match[1] }
        raise ArgumentError, "product is unavailable" unless product

        @telegram_api.answer_callback_query(
          callback_query_id: callback.fetch("id"),
          text: "обрано: #{product.dig("attributes", "name")}"
        )
      end

      def catalog_keyboard(products, callback_prefix:)
        buttons = products.first(CATALOG_PAGE_SIZE).map do |product|
          {
            text: product.dig("attributes", "button_label") || product.dig("attributes", "name"),
            callback_data: "#{callback_prefix}_#{product.fetch("id")}"
          }
        end
        { inline_keyboard: buttons.each_slice(CATALOG_COLUMNS).to_a }
      end

      def show_servers(message)
        user = authenticate(message)
        telegram_user_id = message.fetch("from").fetch("id")
        chat_id = message.fetch("chat").fetch("id")
        broker = remember_authorization(user, telegram_user_id: telegram_user_id, chat_id: chat_id)
        sync_commands(chat_id, broker.status, user, authorized: broker.authorized)
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

      def remember_authorization(user, telegram_user_id:, chat_id:)
        @registry.set_status(
          telegram_user_id: telegram_user_id,
          chat_id: chat_id,
          status: @registry.status(telegram_user_id),
          role: user.dig("attributes", "role")
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

      def send_status_message(chat_id, user, status)
        message = send_message(chat_id, status_message(user, status))
        schedule_message_deletion(chat_id, message)
      end

      def schedule_message_deletion(chat_id, message)
        message_id = message&.fetch("message_id", nil)
        return unless message_id

        delete = -> { @telegram_api.delete_message(chat_id: chat_id, message_id: message_id) }
        return delete.call if @status_message_ttl.zero?

        Thread.new do
          sleep @status_message_ttl
          delete.call
        rescue TelegramAPI::Error => error
          warn "status message deletion failed: #{error.message}"
        end.tap { |thread| thread.report_on_exception = false }
      end

      def sync_commands(chat_id, status, user, authorized:)
        @telegram_api.set_commands(
          commands_for(status, user, authorized: authorized),
          scope: { type: "chat", chat_id: chat_id }
        )
      rescue TelegramAPI::Error => error
        warn "command menu sync failed: #{error.message}"
      end

      def commands_for(status, user, authorized:)
        commands = case status
                   when "paused" then PAUSED_COMMANDS
                   when "ready" then READY_COMMANDS
                   when "busy" then BUSY_COMMANDS
                   else raise ArgumentError, "broker status is invalid"
                   end
        commands = [LIST_COMMAND, *commands] if authorized
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

      def send_message(chat_id, text, reply_markup: nil)
        @telegram_api.send_message(
          chat_id: chat_id,
          text: text,
          reply_markup: reply_markup
        )
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
