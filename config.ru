# frozen_string_literal: true

require "bundler/setup"
require_relative "lib/zero_x_da/market_broker_bot/bot"
require_relative "lib/zero_x_da/market_broker_bot/broker_registry"
require_relative "lib/zero_x_da/market_broker_bot/market_api"
require_relative "lib/zero_x_da/market_broker_bot/telegram_api"
require_relative "lib/zero_x_da/market_broker_bot/web_app"

telegram_api = ZeroXDA::MarketBrokerBot::TelegramAPI.new(
  token: ENV.fetch("TELEGRAM_BOT_TOKEN")
)
market_api = ZeroXDA::MarketBrokerBot::MarketAPI.new(
  base_url: ENV.fetch("MARKET_API_URL", "https://zeroxda-market.onrender.com"),
  operator_token: ENV.fetch("MARKET_OPERATOR_TOKEN")
)
bot = ZeroXDA::MarketBrokerBot::Bot.new(
  market_api: market_api,
  telegram_api: telegram_api,
  registry: ZeroXDA::MarketBrokerBot::BrokerRegistry.new
)

run ZeroXDA::MarketBrokerBot::WebApp.new(
  bot: bot,
  webhook_secret: ENV.fetch("TELEGRAM_WEBHOOK_SECRET")
)
