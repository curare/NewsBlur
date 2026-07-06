#!/usr/bin/env bash
set -euo pipefail

REMOTE=ovh
REMOTE_DIR=/opt/tinkdeck/NewsBlur
COMPOSE="sudo docker compose -f docker-compose.yml -f docker-compose.vps.yml"

echo "==> Pushing local changes..."
git push

echo "==> Pulling on server..."
ssh "$REMOTE" "cd $REMOTE_DIR && sudo git pull --ff-only"

echo "==> Reconciling containers with current compose..."
ssh "$REMOTE" "cd $REMOTE_DIR && $COMPOSE up -d --remove-orphans"

echo "==> Done. Deployed to https://news.tinkdeck.com"
