# frozen_string_literal: true

require "monitor"

module ZeroXDA
  module MarketBrokerBot
    class BrokerRegistry
      Broker = Data.define(:telegram_user_id, :chat_id, :status, :role)
      STATUSES = %w[ready busy paused].freeze
      ROLES = %w[broker admin].freeze

      def initialize
        @brokers = {}
        @monitor = Monitor.new
      end

      def set_status(telegram_user_id:, chat_id:, status:, role: "broker")
        status = status.to_s
        role = role.to_s
        raise ArgumentError, "broker status is invalid" unless STATUSES.include?(status)
        raise ArgumentError, "broker role is invalid" unless ROLES.include?(role)

        broker = Broker.new(
          telegram_user_id: telegram_user_id.to_s,
          chat_id: chat_id.to_s,
          status: status,
          role: role
        )
        @monitor.synchronize { @brokers[broker.telegram_user_id] = broker }
        broker
      end

      def status(telegram_user_id)
        @monitor.synchronize { @brokers[telegram_user_id.to_s]&.status || "paused" }
      end

      def fetch(telegram_user_id, chat_id:)
        @monitor.synchronize do
          @brokers[telegram_user_id.to_s] || Broker.new(
            telegram_user_id: telegram_user_id.to_s,
            chat_id: chat_id.to_s,
            status: "paused",
            role: "broker"
          )
        end
      end
    end
  end
end
