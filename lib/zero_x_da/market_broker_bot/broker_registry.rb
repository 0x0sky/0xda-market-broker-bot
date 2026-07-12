# frozen_string_literal: true

require "monitor"

module ZeroXDA
  module MarketBrokerBot
    class BrokerRegistry
      Broker = Data.define(:telegram_user_id, :chat_id, :status)
      STATUSES = %w[ready busy paused].freeze

      def initialize
        @brokers = {}
        @monitor = Monitor.new
      end

      def set_status(telegram_user_id:, chat_id:, status:)
        status = status.to_s
        raise ArgumentError, "broker status is invalid" unless STATUSES.include?(status)

        broker = Broker.new(
          telegram_user_id: telegram_user_id.to_s,
          chat_id: chat_id.to_s,
          status: status
        )
        @monitor.synchronize { @brokers[broker.telegram_user_id] = broker }
        broker
      end

      def status(telegram_user_id)
        @monitor.synchronize { @brokers[telegram_user_id.to_s]&.status || "paused" }
      end
    end
  end
end
