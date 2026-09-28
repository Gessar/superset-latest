# superset-latest — отдельный стенд последней версии Apache Superset

Второй, независимый инстанс Superset (не мешает рабочему `simple-superset-compose`):
последний релиз **6.1.0**, свой порт, своя база метаданных, свои драйверы подключений.

| Что | Значение |
|---|---|
| URL | http://localhost:8081 |
| Логин | `admin` / `admin` (меняется в `.env`) |
| Версия | 6.1.0 (`FROM apache/superset:6.1.0`) |
| Контейнер | `superset_latest`, образ `superset-latest-app` |
| Метаданные | SQLite в `./superset_home/superset.db` (опционально PostgreSQL — см. ниже) |

## Быстрый старт

```bash
cd ~/docker_containers/superset-latest
bash scripts/up.sh          # сборка + запуск + ожидание здоровья
open http://localhost:8081   # admin / admin
```

Первый старт занимает ~1–2 минуты: контейнер сам применяет миграции, синхронизирует
роли и права и создаёт администратора из `.env`.

## Структура

```
superset-latest/
├── docker-compose.yml            # сервис superset (+ закомментированный meta-db)
├── .env                          # порт, секрет, первый админ, URI метаданных
├── superset/
│   ├── Dockerfile                # apache/superset:6.1.0 + драйверы подключений
│   ├── extra-requirements.txt    # список драйверов (ставится при сборке)
│   ├── superset_config.py        # секрет, метаданные, санитайз под Handlebars
│   └── docker-entrypoint.sh      # миграции → init → админ → запуск сервера
└── scripts/
    ├── up.sh                     # собрать и поднять стенд
    ├── rebuild.sh                # пересобрать образ и пересоздать контейнер
    └── add-plugin.sh             # ← добавить драйвер подключения в контейнер
```

## Скрипт add-plugin.sh (драйверы подключений)

Голый образ Superset не умеет подключаться ни к чему: для каждой СУБД нужен pip-пакет
со SQLAlchemy-диалектом. Скрипт заходит в контейнер, ставит пакет, проверяет импорт и
перезапускает Superset.

```bash
bash scripts/add-plugin.sh list                 # все псевдонимы (30 СУБД)
bash scripts/add-plugin.sh installed            # что уже установлено
bash scripts/add-plugin.sh clickhouse           # поставить драйвер ClickHouse
bash scripts/add-plugin.sh postgres --persist   # + прописать в образ (переживёт пересборку)
bash scripts/add-plugin.sh trino --no-restart   # без перезапуска
bash scripts/add-plugin.sh some-pip-package     # произвольный pip-пакет
bash scripts/add-plugin.sh shell                # зайти внутрь контейнера (bash)
```

Флаги: `--persist` (дописать в `superset/extra-requirements.txt` → применится после
`bash scripts/rebuild.sh`), `--no-restart`, `--container NAME`.

**Важно:** установка в работающий контейнер живёт до его пересоздания
(`docker compose up -d --build`). Для постоянного эффекта — `--persist` + `rebuild.sh`.

### Куда именно ставится пакет (грабли Superset 5.x/6.x)

В образах 6.x приложение лежит в uv-venv `/app/.venv`, а `pip` в `PATH` — **системный**
(`/usr/local/bin/pip`), причём в самом venv pip отсутствует. Поэтому:

* правильный способ — `uv pip install --python /app/.venv/bin/python <пакет>`;
* установка через `pip install` уйдёт в системный python, Superset драйвер **не увидит**
  (проверено: `ModuleNotFoundError` при живом пакете в `/usr/local/lib/...`).

Скрипт сам определяет установщик (uv → `python -m pip` для более старых образов) и
проверяет импорт именно в интерпретаторе Superset.

## Подключения к БД

Settings → Database Connections → **+ Database** → SQLAlchemy URI:

```
clickhousedb+connect://default:ПАРОЛЬ@CH_HOST:8123/default      # ClickHouse
postgresql+psycopg2://USER:ПАРОЛЬ@PG_HOST:5432/DBNAME           # PostgreSQL
```

Оба драйвера уже в образе. Внутри docker-сети хосты — имена сервисов, для внешних БД — её
адрес. Проверено на этом стенде живыми запросами: ClickHouse — агрегат по своей таблице
деклараций, PostgreSQL — `select 1`.

## Что настроено под Handlebars-чарты

В `superset/superset_config.py`:

* `HTML_SANITIZATION_SCHEMA_EXTENSIONS` — разрешены `class`, `style`, `data-*`, тег
  `<style>` и SVG-элементы (иначе санитайз превращает отчёт в «голый HTML»);
* `ENABLE_TEMPLATE_PROCESSING` — Jinja в SQL датасетов (для фильтров `from_dttm/to_dttm`);
* `FEATURE_FLAGS.ALLOW_ADHOC_SUBQUERY = True` — иначе в 6.x raw-режим таблиц падает с
  «Custom SQL fields cannot contain sub-queries» на русских именах колонок (с пробелами,
  запятыми, префиксом `--`): Superset валидирует имена колонок через sqlglot и не умеет
  их парсить.

Сам чарт `Handlebars` в 6.1.0 на месте (проверено по бандлу: `handlebarsTemplate`
присутствует в `/app/superset/static/assets/*.js`).

## Обслуживание

```bash
bash scripts/rebuild.sh                  # после правки config/Dockerfile/extra-requirements
docker logs -f superset_latest           # логи
docker compose exec superset bash         # или: bash scripts/add-plugin.sh shell
```

Обновить версию Superset: поменять тег в `superset/Dockerfile` (`FROM apache/superset:X.Y.Z`)
и выполнить `bash scripts/rebuild.sh` — миграции метаданных применит entrypoint.

### Метаданные в PostgreSQL (опционально)

1. Раскомментировать сервис `meta-db` в `docker-compose.yml` (версию образа фиксировать:
   `postgres:16-alpine`, а не `postgres:alpine` — иначе новый мажор не стартует на старых данных).
2. В `.env` заполнить `SQLALCHEMY_DATABASE_URI`.
3. `bash scripts/rebuild.sh`.

## Грабли, на которые уже наступили

| Симптом | Причина | Решение |
|---|---|---|
| `unable to open database file` при старте | каталог `superset_home` создан docker'ом как root, а Superset работает под uid 1000 | `mkdir -p superset_home && chmod 777 superset_home` (делает `up.sh`); entrypoint теперь сообщает об этом прямо |
| `ModuleNotFoundError` у драйвера, хотя пакет установлен | установили через `pip` из PATH → в системный python, а не в venv `/app/.venv` | `uv pip install --python /app/.venv/bin/python …` (делает `add-plugin.sh`) |
| 500 на всех страницах после обновления версии | метаданные не мигрированы | entrypoint выполняет `superset db upgrade` + `superset init` при каждом старте |
| Нет пользователя / «Invalid login» | админ не создан | `.env`: `ADMIN_USERNAME`/`ADMIN_PASSWORD`; создаётся на первом старте |
| «Custom SQL fields cannot contain sub-queries» в таблицах | кириллические имена колонок не парсятся sqlglot в raw-режиме | `ALLOW_ADHOC_SUBQUERY: True` (уже включён) |
| `pip install` в контейнере «прошёл», но драйвера нет | образ 6.x: `pip` = системный | см. `add-plugin.sh`, он ставит через uv |
| SQL Lab: 403 / `TypeError: can't access property 2` | не выполнен `superset init` (права ролей) | уже в entrypoint; вручную: `docker exec superset_latest superset init` |

## Что проверено на этом стенде

* Superset 6.1.0 поднимается с нуля: миграции, роли/права, администратор, `/health` = 200.
* Драйверы в venv: `clickhouse-connect 1.9.0`, `psycopg2 2.9.13` — импортируются тем же
  интерпретатором, в котором работает Superset.
* `add-plugin.sh trino --persist` — установка в живой контейнер, проверка импорта,
  дописывание в `extra-requirements.txt`, перезапуск, health OK.
* Реальные запросы через Superset: ClickHouse (агрегат по таблице деклараций, ~25.7 тыс.
  строк) и PostgreSQL (`select 1`).
* `HTML_SANITIZATION` + расширенная схема, `ENABLE_TEMPLATE_PROCESSING`,
  `ALLOW_ADHOC_SUBQUERY` применяются (проверено через `app.config`).
