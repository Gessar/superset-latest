FROM apache/superset:6.1.0

USER root

# =============================================================================
# Драйверы-«плагины» подключений. У голого образа Superset их НЕТ ни одного
# (проверено: ни clickhouse-connect, ни psycopg2) — без них Superset не увидит
# ни ClickHouse, ни PostgreSQL.
#
# ВАЖНО: в образе 6.x приложение живёт в uv-venv /app/.venv, а pip в PATH —
# системный (/usr/local/bin/pip). Ставить надо ТОЛЬКО через uv в этот venv,
# иначе пакет уйдёт в системный python и Superset его не увидит.
#
# Список лежит в extra-requirements.txt и дополняется скриптом
# scripts/add-plugin.sh --persist <плагин> — после этого нужен пересбор образа.
# =============================================================================
COPY extra-requirements.txt /tmp/extra-requirements.txt
RUN uv pip install --python /app/.venv/bin/python --no-cache -r /tmp/extra-requirements.txt \
 && rm -f /tmp/extra-requirements.txt

# Конфиг (секрет, метаданные, санитайз под Handlebars-чарты)
COPY superset_config.py /app/superset_config.py
RUN chmod 755 /app/superset_config.py
ENV SUPERSET_CONFIG_PATH=/app/superset_config.py

# Свой entrypoint: миграции + init + первый админ, затем штатный run-server.sh
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod 755 /app/docker-entrypoint.sh

USER superset
ENTRYPOINT ["/app/docker-entrypoint.sh"]
