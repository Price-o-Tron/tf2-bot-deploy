# Price-o-Tron Bot Setup

## 1. Environment Setup
- Copy `template.env` to `.env` and fill in your environment variables.
- Copy `bots/template.env` to `bots/bot1.env` and add your bot's account info.

## 2. MinIO Bucket Initialization (Automatic)
To automatically create the required MinIO bucket (`tf2-automatic`), use the provided `docker-compose.init.yml`:

1. Ensure your `.env` file contains `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD`.
2. Run the following command to start MinIO and create the bucket:
   
	```sh
	docker compose -f docker-compose.init.yml up minio-init
	```
	This will start MinIO and a one-off init container that creates the `tf2-automatic` bucket if it does not exist.
3. After the bucket is created, you can stop the init containers:
   
	```sh
	docker compose -f docker-compose.init.yml down
	```

## 3. Start All Services
Start your main stack as usual:

```sh
docker compose up -d
```

----

### Adding More Bots
Copy the `bot1` service template at the bottom of `docker-compose.yml`, rename the service, and update the corresponding env file.