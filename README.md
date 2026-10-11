# Price-o-Tron Bot Setup

## 1. Environment Setup
- Copy `template.env` to `.env` and fill in your environment variables.
- Copy `bots/template.env` to `bots/bot1.env` and add your bot's account info.
- reate `s3_config.json` file from the template at `template.s3_config.json` and make sure seaweed credentials match with `/bots/*.env`

**Make sure that seaweed variables are the same across s3_config.json and bots envs**

## 2. Run the setup (mandatory)
Before you run it, `SECRET_TOKEN` in `.env` must be set (at least 32 characters): it is the token you generated in
Price-o-Tron under Profile -> Generate Encrypted Token. It signs every request that changes your bot's prices.
`./setup.sh` stops with an explanation if it is empty or too short, and the bot itself refuses to start without it.
Signed requests must carry a timestamp within 5 minutes of the server's clock and can be used only once (keep the
server clock in sync with NTP).

HTTPS is part of the stack, so run the setup script once before the first start:

```sh
./setup.sh                    # no domain needed: uses a free hostname like 203-0-113-5.sslip.io
./setup.sh bot.example.com    # or your own domain (its DNS A record must point at this server)
```

The script:
- opens the firewall (installs `ufw` on Debian/Ubuntu, allows SSH, 80/tcp, 443/tcp, 443/udp and enables it; it asks first, use `--yes` to skip the question or `--no-firewall` to skip the step),
- saves `BOT_DOMAIN` in `.env`,
- starts the whole stack with `docker compose up -d`,
- waits until the Let's Encrypt certificate works and prints your HTTPS address.

Ports 80 and 443 must be reachable from the internet (behind a home router, forward them to this machine).
Until `BOT_DOMAIN` is set, `docker compose` refuses to start and tells you to run `./setup.sh`.

Then enter the printed `https://...` address in Price-o-Tron under Profile -> Bot Server Address.
Price-o-Tron only accepts HTTPS domain names (no `http://`, no bare IP addresses). Port 8080 is no longer
open to the internet; the app is reachable from this machine only. Docker-published ports bypass `ufw`.

Redis, Postgres, the RabbitMQ UI, SeaweedFS and the bot API are not published to the internet;
the ones with a web UI are reachable from this machine only (`127.0.0.1`).

----

## 3. Start / restart
```sh
docker compose up -d
```

----

## 4. How to update
docker compose pull && docker compose up -d

### Adding More Bots
Copy the `bot1` service template at the bottom of `docker-compose.yml`, rename the service, and update the corresponding env file.