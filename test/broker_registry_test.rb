require_relative "test_helper"
require "zero_x_da/market_broker_bot/broker_registry"

class BrokerRegistryTest < Minitest::Test
  def test_defaults_to_paused_and_tracks_status
    registry = ZeroXDA::MarketBrokerBot::BrokerRegistry.new

    assert_equal "paused", registry.status(77)
    registry.set_status(telegram_user_id: 77, chat_id: 770, status: "ready")
    assert_equal "ready", registry.status("77")
  end

  def test_rejects_an_unknown_status
    registry = ZeroXDA::MarketBrokerBot::BrokerRegistry.new

    assert_raises(ArgumentError) do
      registry.set_status(telegram_user_id: 77, chat_id: 770, status: "busy")
    end
  end
end
