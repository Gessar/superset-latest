#!/usr/bin/env bash
# =============================================================================
# add-plugin.sh — добавить «плагин» подключения (database engine spec) в
# работающий контейнер Superset.
#
# Superset сам по себе не умеет ни к чему подключаться: для каждой СУБД нужен
# pip-пакет с SQLAlchemy-диалектом. В образе apache/superset их нет — этот скрипт
# заходит в контейнер, ставит пакет, проверяет импорт и перезапускает сервер.
#
# ИСПОЛЬЗОВАНИЕ
#   bash scripts/add-plugin.sh list                     список псевдонимов
#   bash scripts/add-plugin.sh installed                что уже стоит в контейнере
#   bash scripts/add-plugin.sh clickhouse               поставить драйвер ClickHouse
#   bash scripts/add-plugin.sh postgres --persist       ещё и в образ (переживёт пересборку)
#   bash scripts/add-plugin.sh some-pip-package         произвольный pip-пакет
#   bash scripts/add-plugin.sh shell                     зайти в контейнер (bash)
#
# ОПЦИИ
#   --persist      дописать пакет в superset/extra-requirements.txt,
#                  чтобы он ставился при сборке образа (bash scripts/rebuild.sh)
#   --no-restart   не перезапускать контейнер после установки
#   --container N  имя контейнера (по умолчанию superset_latest или $SUPERSET_CONTAINER)
#
# ВАЖНО: установка в работающий контейнер живёт до пересоздания контейнера
# (docker compose up -d --build). Для постоянного эффекта — с флагом --persist.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="${ROOT}/superset/extra-requirements.txt"
HTTP_PORT="${SUPERSET_HTTP_PORT:-8081}"
CONTAINER="${SUPERSET_CONTAINER:-superset_latest}"

# псевдоним → "pip-пакет|модуль для проверки импорта"
declare -A PLUGINS=(
  [clickhouse]="clickhouse-connect|clickhouse_connect"
  [clickhouse-sqlalchemy]="clickhouse-sqlalchemy|clickhouse_sqlalchemy"
  [postgres]="psycopg2-binary|psycopg2"
  [postgres-psycopg3]="psycopg[binary]|psycopg"
  [mysql]="mysqlclient|MySQLdb"
  [mssql]="pymssql|pymssql"
  [oracle]="cx_Oracle|cx_Oracle"
  [trino]="trino|trino"
  [bigquery]="sqlalchemy-bigquery|sqlalchemy_bigquery"
  [snowflake]="snowflake-sqlalchemy|snowflake"
  [redshift]="sqlalchemy-redshift|sqlalchemy_redshift"
  [druid]="pydruid|pydruid"
  [elasticsearch]="elasticsearch-dbapi|es"
  [pinot]="pinotdb|pinotdb"
  [hive]="pyhive|pyhive"
  [kusto]="sqlalchemy-kusto|sqlalchemy_kusto"
  [duckdb]="duckdb-engine|duckdb_engine"
  [starrocks]="starrocks|starrocks"
  [databend]="databend-sqlalchemy|databend_sqlalchemy"
  [firebolt]="firebolt-sqlalchemy|firebolt"
  [exasol]="sqlalchemy-exasol|sqlalchemy_exasol"
  [vertica]="sqlalchemy-vertica-python|sqlalchemy_vertica"
  [teradata]="teradatasqlalchemy|teradatasqlalchemy"
  [db2]="ibm-db-sa|ibm_db_sa"
  [cockroachdb]="sqlalchemy-cockroachdb|sqlalchemy_cockroachdb"
  [mongodb]="pymongo|pymongo"
  [dremio]="sqlalchemy-dremio|sqlalchemy_dremio"
  [netezza]="nzalchemy|nzalchemy"
)

PERSIST=0
RESTART=1
TARGET=""
usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

list_plugins() {
  echo "Псевдонимы для add-plugin.sh (псевдоним → pip-пакет → модуль проверки):"
  for key in $(printf '%s\n' "${!PLUGINS[@]}" | sort); do
    IFS='|' read -r pkg mod <<< "${PLUGINS[$key]}"
    printf '  %-22s %-30s %s\n' "$key" "$pkg" "$mod"
  done
  echo
  echo "Любой другой пакет можно поставить напрямую: add-plugin.sh <pip-имя>"
  echo "Точные имена пакетов Superset перечисляет в docs → Databases → Supported Databases."
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = "true" ]
}

# Интерпретатор, в котором реально работает Superset внутри контейнера.
#   6.x/5.x → uv-venv /app/.venv/bin/python
#   4.1.2 и старше → системный /usr/local/bin/python
interp() {
  docker exec "$CONTAINER" python -c 'import sys; print(sys.executable)' 2>/dev/null \
    || echo /usr/local/bin/python
}

# Установка в тот же интерпретатор, в котором работает Superset.
#   1) uv  — штатный способ для образов 5.x/6.x (venv создан uv, pip внутри нет)
#   2) python -m pip — образы 4.x и старше (пакеты в системном python)
plugin_install() {
  local pkg="$1" py
  py="$(interp)"
  if docker exec "$CONTAINER" sh -c 'command -v uv >/dev/null 2>&1'; then
    echo "== установщик: uv → ${py} =="
    docker exec -u root "$CONTAINER" uv pip install --python "$py" --no-cache "$pkg" 2>&1 | tail -4
  elif docker exec "$CONTAINER" "$py" -m pip --version >/dev/null 2>&1; then
    echo "== установщик: python -m pip → ${py} =="
    docker exec -u root "$CONTAINER" "$py" -m pip install --no-cache-dir "$pkg" 2>&1 | tail -4
  else
    echo "ОШИБКА: не нашёл ни uv, ни pip — поставьте пакет через extra-requirements.txt + rebuild" >&2
    return 1
  fi
}

plugin_list() {
  local py
  py="$(interp)"
  if docker exec "$CONTAINER" sh -c 'command -v uv >/dev/null 2>&1'; then
    docker exec "$CONTAINER" uv pip list --python "$py" 2>/dev/null
  else
    docker exec "$CONTAINER" "$py" -m pip list 2>/dev/null
  fi
}

require_container() {
  if ! container_running; then
    echo "ОШИБКА: контейнер '${CONTAINER}' не запущен." >&2
    echo "Поднимите стенд: bash scripts/up.sh" >&2
    exit 1
  fi
}

persist() {
  local pkg="$1"
  touch "$REQ_FILE"
  if grep -qE "^${pkg//[/]/\\[}([[:space:]]|$)" "$REQ_FILE"; then
    echo "  · ${pkg} уже есть в extra-requirements.txt"
  else
    printf '%s\n' "$pkg" >> "$REQ_FILE"
    echo "  · ${pkg} дописан в superset/extra-requirements.txt — применится при bash scripts/rebuild.sh"
  fi
}

install_plugin() {
  local pkg="$1" mod="${2:-}"
  echo "== контейнер: ${CONTAINER} =="
  echo "== целевой интерпретатор (в нём работает Superset): $(interp) =="
  plugin_install "$pkg"

  if [ -n "$mod" ]; then
    if docker exec "$CONTAINER" "$(interp)" -c "import ${mod}" >/dev/null 2>&1; then
      echo "== проверка: модуль ${mod} импортируется в интерпретаторе Superset =="
    else
      echo "== ВНИМАНИЕ: модуль ${mod} не импортируется — проверьте имя пакета вручную =="
    fi
  fi

  if [ "$PERSIST" = "1" ]; then
    persist "$pkg"
  fi

  if [ "$RESTART" = "1" ]; then
    echo "== перезапуск Superset (драйверы читаются на старте) =="
    docker restart "$CONTAINER" >/dev/null
    echo -n "   ждём health: "
    for _ in $(seq 1 40); do
      if curl -fsS -m 5 "http://localhost:${HTTP_PORT}/health" >/dev/null 2>&1; then
        echo "OK (http://localhost:${HTTP_PORT})"; break
      fi
      echo -n "."; sleep 3
    done
  fi

  echo
  echo "Дальше в Superset: Settings → Database Connections → + Database →"
  echo "вставить SQLAlchemy URI (внутри docker-сети хосты — имена сервисов;"
  echo "для внешней БД — её IP/хост, например clickhousedb+connect://default:@10.0.0.5:8123/default)."
}

# ------------------------------- разбор аргументов -------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --list|list) list_plugins; exit 0 ;;
    --persist) PERSIST=1; shift ;;
    --no-restart) RESTART=0; shift ;;
    --container) CONTAINER="${2:?нужно имя контейнера}"; shift 2 ;;
    installed)
      require_container
      echo "Интерпретатор Superset: $(interp)"
      echo "Установленные драйверы в ${CONTAINER}:"
      plugin_list | grep -iE 'clickhouse|psycopg|trino|mysql|pymssql|cx-oracle|snowflake|bigquery|redshift|pydruid|pinot|pyhive|duckdb|starrocks|teradatasql|ibm-db|pymongo|elasticsearch|exasol|vertica' || echo "  (ничего из известных драйверов)"
      exit 0 ;;
    shell)
      require_container
      exec docker exec -it "$CONTAINER" bash ;;
    -*) echo "неизвестная опция: $1" >&2; usage 1 ;;
    *) TARGET="$1"; shift ;;
  esac
done

[ -n "$TARGET" ] || usage 1

require_container

if [ -n "${PLUGINS[$TARGET]:-}" ]; then
  IFS='|' read -r pkg mod <<< "${PLUGINS[$TARGET]}"
  install_plugin "$pkg" "$mod"
else
  echo "псевдоним '${TARGET}' не найден — ставлю как pip-пакет"
  install_plugin "$TARGET" ""
fi
