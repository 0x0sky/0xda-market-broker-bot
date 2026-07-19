# 0xda-market Broker Bot

Dedicated Telegram operator service for `0xda-market`.

The first implementation authenticates a Telegram identity as a trusted
`broker` through the market operator API and controls whether that broker is
ready to receive new requests.

## Commands

- `/start` — authenticate and become `ready`;
- `/ready` — receive new requests;
- `/pause` — pause new request notifications;
- `/status` — show the persisted market role and current bot status; the response
  is removed after three seconds.
- `/list` — open the product catalog and choose a product to list (authenticated
  broker context only).
- `/servers` — show core and broker-bot health with UTC server times (admin only).

The default Telegram menu exposes only `/start`. After authentication, the
private chat command scope follows the current broker status:

- `paused` — `/list`, `/ready` and `/status`;
- `ready` — `/list`, `/pause` and `/status`;
- `busy` — `/list` and `/status`.

Before broker authentication, even a cold-start `/status` response omits
`/list`. The command loads `GET /operator/v1/products` from the core and renders
the first nine products as a 3×3 inline keyboard. Product callbacks use the
stable `add_<sku>` contract; catalog rows are never hardcoded in the bot.

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

## Environments

Test and production use separate Telegram bots and Render services. Code reaches
production through a pull request from `master` to the protected `release`
branch. Render deploys only after the `test` CI check passes.

| | test | production |
| --- | --- | --- |
| Git branch | `master` | `release` |
| Render service | `0xda-market-test-broker-bot` | `0xda-market-broker-bot` |
| `MARKET_API_URL` | `https://zeroxda-market-test.onrender.com` | `https://zeroxda-market.onrender.com` |
| `MARKET_OPERATOR_TOKEN` | test core `MANUAL_PROVIDER_TOKEN` | production core `MANUAL_PROVIDER_TOKEN` |

- `TELEGRAM_BOT_TOKEN` — token for `@zeroxda_market_broker_bot`;
- `TELEGRAM_WEBHOOK_SECRET` — random webhook secret for Telegram requests;
- `MARKET_API_URL` — matching core URL for the same environment;
- `MARKET_OPERATOR_TOKEN` — must equal the core `MANUAL_PROVIDER_TOKEN`;
- `PUBLIC_URL` — deployed broker-bot URL without a trailing slash.

Secrets must be configured separately on each Render service and must not be
committed.

## Run

Ruby `3.3.11` is required.

```sh
bundle install
bundle exec rake
bundle exec ruby bin/start
```
