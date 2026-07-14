require_relative "test_helper"
require "zero_x_da/market_broker_bot/broker_registry"

class BrokerRegistryTest < Minitest::Test
  def test_defaults_to_paused_and_tracks_status
    registry = ZeroXDA::MarketBrokerBot::BrokerRegistry.new

    assert_equal "paused", registry.status(77)
    registry.set_status(telegram_user_id: 77, chat_id: 770, status: "ready")
    assert_equal "ready", registry.status("77")
    assert_equal "broker", registry.fetch(77, chat_id: 770).role
    assert registry.fetch(77, chat_id: 770).authorized
  end

  def test_rejects_an_unknown_status
    registry = ZeroXDA::MarketBrokerBot::BrokerRegistry.new

    assert_raises(ArgumentError) do
      registry.set_status(telegram_user_id: 77, chat_id: 770, status: "offline")
    end
  end

  def test_tracks_busy_status
    registry = ZeroXDA::MarketBrokerBot::BrokerRegistry.new

    registry.set_status(telegram_user_id: 77, chat_id: 770, status: "busy")

    assert_equal "busy", registry.status(77)
  end

  def test_tracks_admin_role_and_defaults_unknown_brokers_to_paused
    registry = ZeroXDA::MarketBrokerBot::BrokerRegistry.new

    unknown = registry.fetch(77, chat_id: 770)
    assert_equal "paused", unknown.status
    assert_equal "broker", unknown.role
    refute unknown.authorized

    registry.set_status(
      telegram_user_id: 99,
      chat_id: 990,
      status: "ready",
      role: "admin"
    )
    assert_equal "admin", registry.fetch(99, chat_id: 990).role
  end
end
