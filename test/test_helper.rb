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
  attr_reader :messages, :command_sets, :deleted_messages

  def initialize
    @messages = []
    @command_sets = []
    @deleted_messages = []
  end

  def send_message(chat_id:, text:, reply_markup: nil)
    message = {
      "message_id" => @messages.length + 1,
      chat_id: chat_id,
      text: text,
      reply_markup: reply_markup
    }
    @messages << message
    message
  end

  def delete_message(chat_id:, message_id:)
    @deleted_messages << { chat_id: chat_id, message_id: message_id }
  end

  def set_commands(commands, scope: nil)
    @command_sets << { commands: commands, scope: scope }
  end
end
