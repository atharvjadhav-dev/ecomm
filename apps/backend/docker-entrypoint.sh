#!/bin/sh
set -e

echo "[medusa-backend] Starting container entrypoint..."

# If default start command is invoked, execute database migrations before booting
if [ "$1" = "medusa" ] && [ "$2" = "start" ] || [ "$#" -eq 0 ]; then
  echo "[medusa-backend] Running database migrations..."
  npx medusa db:migrate
  echo "[medusa-backend] Migrations completed successfully."

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
