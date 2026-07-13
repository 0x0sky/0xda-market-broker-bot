$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"

class FakeMarketAPI
  attr_reader :requests, :health_requests

  def initialize
    @requests = []
    @health_requests = 0
  end

  def authenticate_telegram(user:, chat:)
    @requests << { user: user, chat: chat }
    role = user.fetch("id").to_s == "99" ? "admin" : "broker"
    {
      "id" => "12345678-1234-4000-8000-123456789012",
      "attributes" => { "role" => role, "status" => "active" }
    }
  end

  def health
    @health_requests += 1
    { "status" => "ok", "server_time" => "2026-07-12T00:00:00.000000Z" }
  end
end

class FakeTelegramAPI
  attr_reader :messages, :command_sets

  def initialize
    @messages = []
    @command_sets = []
  end

  def send_message(chat_id:, text:, reply_markup: nil)
    @messages << { chat_id: chat_id, text: text, reply_markup: reply_markup }
  end

  def set_commands(commands, scope: nil)
    @command_sets << { commands: commands, scope: scope }
  end
end
