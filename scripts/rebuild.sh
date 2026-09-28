#!/usr/bin/env bash
# Пересобрать образ (после правки superset_config.py, Dockerfile или extra-requirements.txt)
# и пересоздать контейнер с ожиданием здоровья.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
if [ -f .env ]; then set -a; . ./.env; set +a; fi
PORT="${SUPERSET_HTTP_PORT:-8081}"
CONTAINER="${SUPERSET_CONTAINER:-superset_latest}"

# см. up.sh: каталог метаданных должен быть записываемым для uid 1000
mkdir -p superset_home && chmod 777 superset_home

echo "== build =="
docker compose build 2>&1 | tail -4

echo "== recreate =="
docker compose up -d --no-deps --force-recreate superset 2>&1 | tail -4

echo "== health =="
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://localhost:${PORT}/health" || true)
  if [ "$code" = "200" ]; then
    echo "   OK (попытка $i) — http://localhost:${PORT}"
    exit 0
  fi
  sleep 5
done

echo "   не дождались здоровья, последние строки лога:" >&2
docker logs --tail 20 "$CONTAINER" >&2
exit 1
