#!/bin/sh
set -e

echo "[medusa-backend] Starting container entrypoint..."

# If default start command is invoked, execute database migrations before booting
if [ "$1" = "medusa" ] && [ "$2" = "start" ] || [ "$#" -eq 0 ]; then
  echo "[medusa-backend] Running database migrations..."
  npx medusa db:migrate
  echo "[medusa-backend] Migrations completed successfully."

  # Idempotent initial seed & publishable key synchronization for fresh databases
  NEED_SEED=$(node -e '
    const { Client } = require("pg");
    (async () => {
      const client = new Client({
        connectionString: process.env.DATABASE_URL,
        ssl: process.env.DATABASE_SSL === "true" ? { rejectUnauthorized: false } : false,
      });
      await client.connect();
      const res = await client.query("SELECT COUNT(*)::int AS cnt FROM region WHERE deleted_at IS NULL");
      await client.end();
      process.stdout.write(res.rows[0].cnt === 0 ? "true" : "false");
    })().catch(() => process.stdout.write("false"));
  ')

  if [ "$NEED_SEED" = "true" ] && [ -f "src/scripts/seed.ts" ]; then
    echo "[medusa-backend] Fresh database detected (0 regions). Running initial seed..."
    npx medusa exec ./src/scripts/seed.ts || echo "[medusa-backend] Warning: initial seed exited non-zero, continuing."
  fi

  if [ -n "$STOREFRONT_PUBLISHABLE_KEY" ]; then
    echo "[medusa-backend] Synchronizing STOREFRONT_PUBLISHABLE_KEY with publishable api_key..."
    node -e '
      const { Client } = require("pg");
      (async () => {
        const client = new Client({
          connectionString: process.env.DATABASE_URL,
          ssl: process.env.DATABASE_SSL === "true" ? { rejectUnauthorized: false } : false,
        });
        await client.connect();
        await client.query(
          "UPDATE api_key SET token = $1 WHERE type = '\''publishable'\'' AND deleted_at IS NULL",
          [process.env.STOREFRONT_PUBLISHABLE_KEY]
        );
        await client.end();
      })().catch((err) => console.error("[medusa-backend] Key sync warning:", err.message));
    '
  fi

  if [ -d ".medusa/server/public/admin" ] && [ ! -d "public/admin" ]; then
    echo "[medusa-backend] Preparing admin assets..."
    mkdir -p public
    cp -r .medusa/server/public/admin public/admin
  fi

  echo "[medusa-backend] Launching Medusa server..."
  exec npx medusa start
else
  exec "$@"
fi
