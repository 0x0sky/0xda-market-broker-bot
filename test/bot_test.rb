require_relative "test_helper"
require "zero_x_da/market_broker_bot/bot"
require "zero_x_da/market_broker_bot/broker_registry"

class BotTest < Minitest::Test
  def setup
    @market = FakeMarketAPI.new
    @telegram = FakeTelegramAPI.new
    @registry = ZeroXDA::MarketBrokerBot::BrokerRegistry.new
    @bot = ZeroXDA::MarketBrokerBot::Bot.new(
      market_api: @market,
      telegram_api: @telegram,
      registry: @registry
    )
  end

  def test_start_authenticates_broker_and_becomes_ready
    @bot.handle(update("/start"))

    assert_equal 1, @market.requests.length
    assert_equal "ready", @registry.status(77)
    text = @telegram.messages.first.fetch(:text)
    assert_includes text, "авторизація успішна"
    assert_includes text, "role: broker"
    assert_includes text, "status: ready"
  end

  def test_pause_authenticates_and_pauses_broker
    @bot.handle(update("/ready"))
    @bot.handle(update("/pause"))

    assert_equal "paused", @registry.status(77)
    assert_includes @telegram.messages.last.fetch(:text), "status: paused"
  end

  def test_status_reports_current_status_without_changing_it
    @bot.handle(update("/ready"))
    @bot.handle(update("/status"))

    assert_equal "ready", @registry.status(77)
    assert_includes @telegram.messages.last.fetch(:text), "status: ready"
  end

  def test_ready_chat_hides_start_and_ready_commands
    @bot.handle(update("/start"))

    command_set = @telegram.command_sets.last
    assert_equal({ type: "chat", chat_id: "770" }, command_set.fetch(:scope))
    assert_equal %w[pause status], command_names(command_set)
  end

  def test_paused_chat_shows_ready_but_hides_start_and_pause_commands
    @bot.handle(update("/pause"))

    assert_equal %w[ready status], command_names(@telegram.command_sets.last)
  end

  def test_busy_chat_shows_only_status
    @registry.set_status(telegram_user_id: 77, chat_id: 770, status: "busy")

    @bot.handle(update("/status"))

    assert_equal %w[status], command_names(@telegram.command_sets.last)
    assert_includes @telegram.messages.last.fetch(:text), "status: busy"
  end

  def test_commands_cannot_move_a_busy_broker_out_of_busy
    @registry.set_status(telegram_user_id: 77, chat_id: 770, status: "busy")

    %w[/start /ready /pause].each { |command| @bot.handle(update(command)) }

    assert_equal "busy", @registry.status(77)
    assert_equal %w[status], command_names(@telegram.command_sets.last)
  end

  def test_ignores_unknown_messages_and_non_private_chats
    @bot.handle(update("hello"))
    @bot.handle(update("/start", chat_type: "group"))

    assert_empty @market.requests
    assert_empty @telegram.messages
  end

  def test_accepts_command_with_bot_username
    @bot.handle(update("/ready@zeroxda_market_broker_bot"))

    assert_equal "ready", @registry.status(77)
  end

  private

  def command_names(command_set)
    command_set.fetch(:commands).map { |item| item.fetch(:command) }
  end

  def update(text, chat_type: "private")
    {
      "message" => {
        "text" => text,
        "from" => {
          "id" => 77,
          "username" => "zero",
          "first_name" => "Sasha",
          "language_code" => "uk"
        },
        "chat" => { "id" => 770, "type" => chat_type }
      }
    }
  end
end
