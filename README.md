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

The default Telegram menu exposes only `/start`. After authentication, the
broker's private chat scope also receives `/ready`, `/pause` and `/status`.
The service intentionally has no public `/health` route.

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
