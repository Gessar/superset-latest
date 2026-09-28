FROM apache/superset:4.1.2

USER root

# =============================================================================
# Драйверы-«плагины» подключений. У голого образа Superset их НЕТ ни одного
# (проверено: ни clickhouse-connect, ни psycopg2) — без них Superset не увидит
# ни ClickHouse, ни PostgreSQL.
#
# ВАЖНО (отличие от веток main / 6.1.0): образ 4.1.2 запускает Superset из
# СИСТЕМНОГО python (/usr/local/bin/python), никакого venv в нём нет — поэтому
# драйверы ставим обычным pip. В 5.x/6.x приложение живёт в uv-venv /app/.venv,
# и там нужен `uv pip install --python /app/.venv/bin/python`.
#
# Список лежит в extra-requirements.txt и дополняется скриптом
# scripts/add-plugin.sh --persist <плагин> — после этого нужен пересбор образа.
# =============================================================================
COPY extra-requirements.txt /tmp/extra-requirements.txt
RUN pip install --no-cache-dir -r /tmp/extra-requirements.txt && rm -f /tmp/extra-requirements.txt

# Конфиг (секрет, метаданные, санитайз под Handlebars-чарты)
COPY superset_config.py /app/superset_config.py
RUN chmod 755 /app/superset_config.py
ENV SUPERSET_CONFIG_PATH=/app/superset_config.py

# Свой entrypoint: миграции + init + первый админ, затем штатный run-server.sh
# (в 4.1.2 run-server.sh запускает только gunicorn — ни миграций, ни init,
#  ни создания администратора он не делает).
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod 755 /app/docker-entrypoint.sh

USER superset
ENTRYPOINT ["/app/docker-entrypoint.sh"]
