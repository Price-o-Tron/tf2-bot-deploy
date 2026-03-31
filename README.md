# Price-o-Tron Bot Setup

## 1. Environment Setup
- Copy `template.env` to `.env` and fill in your environment variables.
- Copy `bots/template.env` to `bots/bot1.env` and add your bot's account info.
- reate `s3_config.json` file from the template at `template.s3_config.json` and make sure seaweed credentials match with `/bots/*.env`

**Make sure that seaweed variables are the same across s3_config.json and bots envs**

## 3. Start All Services
Start your main stack as usual:

```sh
docker compose up -d
```

----

### Adding More Bots
Copy the `bot1` service template at the bottom of `docker-compose.yml`, rename the service, and update the corresponding env file.