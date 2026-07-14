# 0xda-market Broker Bot

Dedicated Telegram operator service for `0xda-market`.

The first implementation authenticates a Telegram identity as a trusted
`broker` through the market operator API and controls whether that broker is
ready to receive new requests.

## Commands

- `/start` — authenticate and become `ready`;
- `/ready` — receive new requests;
- `/pause` — pause new request notifications;
- `/status` — show the persisted market role and current bot status.
- `/servers` — show core and broker-bot health with UTC server times (admin only).

The default Telegram menu exposes only `/start`. After authentication, the
private chat command scope follows the current broker status:

- `paused` — `/ready` and `/status`;
- `ready` — `/pause` and `/status`;
- `busy` — `/status` only.

An administrator also receives `/servers` in every authenticated broker-state
menu. Brokers do not see it, and manually typing it is denied after the
persisted role is checked through the core API.

The authorization command disappears after authentication. Commands typed
manually cannot move a busy broker out of `busy`. Render and deployment
automation use the public `/health` route, which reports service status and UTC
server time without exposing broker or market data.

Broker presence is currently process-local. Durable presence and pending-task
notifications belong to the next queue-delivery step; the broker identity and
role are already persisted by the market core.

## Environment

- `TELEGRAM_BOT_TOKEN` — token for `@zeroxda_market_broker_bot`;
- `TELEGRAM_WEBHOOK_SECRET` — generated random webhook secret;
- `MARKET_API_URL` — defaults to `https://zeroxda-market.onrender.com`;
- `MARKET_OPERATOR_TOKEN` — must equal the core `MANUAL_PROVIDER_TOKEN`;
- `PUBLIC_URL` — deployed broker-bot URL without a trailing slash.

Secrets must be configured in Render and must not be committed.

## Run

Ruby `3.3.11` is required.

```sh
bundle install
bundle exec rake
bundle exec ruby bin/start
```
