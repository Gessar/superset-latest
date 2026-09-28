#!/usr/bin/env bash
# =============================================================================
# Entrypoint стенда superset-latest:
#   1) миграции метаданных      (superset db upgrade)
#   2) роли и права             (superset init)
#   3) первый администратор     (только если его ещё нет)
#   4) штатный запуск сервера   (/usr/bin/run-server.sh → gunicorn)
#
# Голый образ apache/superset этого не делает: его run-server.sh запускает только
# gunicorn, поэтому на пустой базе Superset отдаёт 500 и работать с ним нельзя.
# =============================================================================
set -euo pipefail

: "${ADMIN_USERNAME:=admin}"
: "${ADMIN_PASSWORD:=admin}"
: "${ADMIN_EMAIL:=admin@localhost}"
: "${ADMIN_FIRSTNAME:=Superset}"
: "${ADMIN_LASTNAME:=Admin}"

if [ -z "${SUPERSET_SECRET_KEY:-}" ]; then
  echo "[entrypoint] ОШИБКА: не задан SUPERSET_SECRET_KEY (см. .env)" >&2
  exit 1
fi

echo "[entrypoint] версия Superset: $(superset version 2>/dev/null | tail -1 || echo '?')"

# Метаданные пишутся в SUPERSET_HOME (./superset_home на хосте). Если каталог
# создан docker'ом как root, пользователь контейнера (uid 1000 superset) в него
# писать не может — Superset падает с «unable to open database file».
if [ ! -w /app/superset_home ]; then
  echo "[entrypoint] ОШИБКА: /app/superset_home недоступен для записи (bind-mount)." >&2
  echo "             На хосте выполните: mkdir -p superset_home && chmod 777 superset_home" >&2
  exit 1
fi

echo "[entrypoint] применяю миграции метаданных (superset db upgrade)"
superset db upgrade

echo "[entrypoint] синхронизирую роли и права (superset init)"
superset init

if superset fab list-users 2>/dev/null | grep -qw -- "${ADMIN_USERNAME}"; then
  echo "[entrypoint] пользователь '${ADMIN_USERNAME}' уже существует — пароль не меняю"
else
  echo "[entrypoint] создаю администратора '${ADMIN_USERNAME}'"
  superset fab create-admin \
    --username "${ADMIN_USERNAME}" \
    --firstname "${ADMIN_FIRSTNAME}" \
    --lastname "${ADMIN_LASTNAME}" \
    --email "${ADMIN_EMAIL}" \
    --password "${ADMIN_PASSWORD}"
fi

echo "[entrypoint] стартую сервер"
exec /usr/bin/run-server.sh
