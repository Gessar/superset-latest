#!/usr/bin/env bash
# Поднять стенд: собрать образ (Superset 6.1.0 + драйверы), запустить, дождаться здоровья.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
if [ -f .env ]; then set -a; . ./.env; set +a; fi
PORT="${SUPERSET_HTTP_PORT:-8082}"
CONTAINER="${SUPERSET_CONTAINER:-superset_412}"

# Каталог метаданных монтируется в контейнер, где Superset работает под uid 1000.
# Если его создаст docker, он будет root:root 755 → «unable to open database file».
mkdir -p superset_home && chmod 777 superset_home

echo "== сборка образа =="
docker compose build 2>&1 | tail -4
echo "== запуск =="
docker compose up -d --remove-orphans 2>&1 | tail -4

echo "== ожидание (первый старт: миграции + создание админа) =="
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://localhost:${PORT}/health" || true)
  if [ "$code" = "200" ]; then
    echo "   health OK на попытке $i"
    break
  fi
  [ "$i" = "60" ] && { echo "   не дождались — смотрите: docker logs ${CONTAINER}"; exit 1; }
  sleep 5
done

echo
echo "Superset готов:  http://localhost:${PORT}"
echo "Логин:           ${ADMIN_USERNAME:-admin} / ${ADMIN_PASSWORD:-admin}  (из .env)"
echo "Версия:          $(docker exec "$CONTAINER" python -c 'import importlib.metadata as m; print(m.version("apache-superset"))' 2>/dev/null || echo '?')"
echo
echo "Драйверы подключений: bash scripts/add-plugin.sh installed"
echo "Добавить драйвер:     bash scripts/add-plugin.sh clickhouse --persist"
