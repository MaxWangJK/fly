#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
email=${1:?Usage: install.sh your-real-email@example.com}
test -f .env || { echo 'Copy .env.example to .env and set secrets first.' >&2; exit 1; }
docker compose config --quiet
mkdir -p deploy/certbot deploy/letsencrypt
docker compose up -d --build postgres api
if [ ! -f deploy/letsencrypt/live/world-workshop.cn/fullchain.pem ]; then
  docker run --rm -p 80:80 \
    -v "$PWD/deploy/letsencrypt:/etc/letsencrypt" \
    -v "$PWD/deploy/certbot:/var/www/certbot" \
    certbot/certbot certonly --standalone --agree-tos --email "$email" -d world-workshop.cn
fi
docker compose up -d nginx
curl --fail --retry 12 --retry-delay 5 --retry-connrefused https://world-workshop.cn/api/health
