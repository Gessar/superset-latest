# superset-latest — стенд Apache Superset, ветка **4.1.2**

Версия-ветка репозитория `superset-latest`: тот же стенд (отдельный инстанс Superset,
свои метаданные, свои драйверы подключений), но пришпиленный к **4.1.2**.

| Что | Значение |
|---|---|
| URL | http://localhost:8082 |
| Логин | `admin` / `admin` (меняется в `.env`) |
| Версия | 4.1.2 (`FROM apache/superset:4.1.2`) |
| Контейнер / образ | `superset_412` / `superset-412-app` |
| Метаданные | SQLite в `./superset_home/superset.db` (опционально PostgreSQL — см. ниже) |

## Быстрый старт

```bash
cd ~/docker_containers/superset-latest      # или отдельный worktree, см. ниже
cp .env.example .env                         # секрет сгенерируйте: openssl rand -hex 32
bash scripts/up.sh                           # сборка + запуск + ожидание здоровья
# http://localhost:8082 — admin / admin
```

Первый старт — 1–2 минуты: контейнер сам применяет миграции, синхронизирует роли и права
и создаёт администратора из `.env`.

## Чем эта ветка отличается от `main` (6.1.0)

| | ветка `4.1.2` | ветка `main` (6.1.0) |
|---|---|---|
| Базовый образ | `apache/superset:4.1.2` | `apache/superset:6.1.0` |
| Python | системный `/usr/local/bin/python`, venv нет | uv-venv `/app/.venv` (pip внутри отсутствует) |
| Установка драйверов при сборке | `pip install -r extra-requirements.txt` | `uv pip install --python /app/.venv/bin/python -r …` |
| Порт по умолчанию | 8082 | 8081 |
| Контейнер / образ | `superset_412` / `superset-412-app` | `superset_latest` / `superset-latest-app` |
| SQL Lab API | принимает `json: true` | `json` убран из `ExecutePayloadSchema` |

Остальное одинаково: свой entrypoint (миграции → `init` → админ → сервер), скрипт
`add-plugin.sh` (сам определяет интерпретатор), конфиг с санитайзом под Handlebars-чарты.
`scripts/add-plugin.sh` и `scripts/*.sh` берут имя контейнера и порт из `.env`
(`SUPERSET_CONTAINER`, `SUPERSET_HTTP_PORT`) — поэтому **обе версии можно держать поднятыми
одновременно**, например через worktree:

```bash
git -C ~/docker_containers/superset-latest worktree add ~/docker_containers/superset-412 4.1.2
cd ~/docker_containers/superset-412 && cp .env.example .env && bash scripts/up.sh
# 6.1.0 остаётся на :8081 (контейнер superset_latest), 4.1.2 поднимается на :8082
```

## Структура

```
├── docker-compose.yml            # сервис superset (+ закомментированный meta-db)
├── .env.example                  # порт, имена контейнера/образа, секрет, первый админ
├── superset/
│   ├── Dockerfile                # apache/superset:4.1.2 + драйверы подключений
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
со SQLAlchemy-диалектом. Скрипт заходит в контейнер, ставит пакет **в тот же интерпретатор,
в котором работает Superset** (здесь это `/usr/local/bin/python`), проверяет импорт и
перезапускает Superset.

```bash
bash scripts/add-plugin.sh list                 # все псевдонимы (30 СУБД)
bash scripts/add-plugin.sh installed            # интерпретатор + что уже установлено
bash scripts/add-plugin.sh clickhouse           # поставить драйвер ClickHouse
bash scripts/add-plugin.sh postgres --persist   # + прописать в образ (переживёт пересборку)
bash scripts/add-plugin.sh trino --no-restart   # без перезапуска
bash scripts/add-plugin.sh some-pip-package     # произвольный pip-пакет
bash scripts/add-plugin.sh shell                # зайти внутрь контейнера (bash)
```

Флаги: `--persist` (дописать в `superset/extra-requirements.txt` → применится после
`bash scripts/rebuild.sh`), `--no-restart`, `--container NAME`.

Постоянная установка — только через `--persist` + `rebuild.sh`: пакет, поставленный в
живой контейнер, исчезнет при его пересоздании.

## Подключения к БД

Settings → Database Connections → **+ Database** → SQLAlchemy URI:

```
clickhousedb+connect://default:ПАРОЛЬ@CH_HOST:8123/default      # ClickHouse
postgresql+psycopg2://USER:ПАРОЛЬ@PG_HOST:5432/DBNAME           # PostgreSQL
```

Оба драйвера уже в образе. Внутри docker-сети хосты — имена сервисов, для внешних БД — её
адрес. Проверено на этом стенде живыми запросами: ClickHouse — агрегат по своей таблице
деклараций (~25.7 тыс. строк), PostgreSQL — `select 1`.

## Что настроено под Handlebars-чарты

В `superset/superset_config.py`:

* `HTML_SANITIZATION_SCHEMA_EXTENSIONS` — разрешены `class`, `style`, `data-*`, тег
  `<style>` и SVG-элементы (иначе санитайз превращает отчёт в «голый HTML»);
* `ENABLE_TEMPLATE_PROCESSING` — Jinja в SQL датасетов (для фильтров `from_dttm/to_dttm`);
* `FEATURE_FLAGS.ALLOW_ADHOC_SUBQUERY = True` — иначе raw-режим таблиц падает с
  «Custom SQL fields cannot contain sub-queries» на русских именах колонок (с пробелами,
  запятыми, префиксом `--`): Superset валидирует имена колонок через sqlglot и не умеет
  их парсить. В 4.1.2 проверено на живом инстансе с русскими датасетами.

Чарт `Handlebars` в 4.1.2 на месте (проверено по бандлу: `handlebarsTemplate` есть в
`/app/superset/static/assets/*.js`).

## Обслуживание

```bash
bash scripts/rebuild.sh                  # после правки config/Dockerfile/extra-requirements
docker logs -f superset_412              # логи
docker compose exec superset bash         # или: bash scripts/add-plugin.sh shell
```

Обновить версию: поменять тег в `superset/Dockerfile` (`FROM apache/superset:X.Y.Z`) и
выполнить `bash scripts/rebuild.sh` — миграции метаданных применит entrypoint.

### Переезд с 3.0.2 (если принесли старую базу метаданных)

Метаданные 3.0.2 не совместимы с 4.1.2 «как есть»: у `slices` появились новые колонки
(`catalog_perm` и др.), поэтому API дашбордов отдаёт 500 (`no such column`), а SQL Lab —
403 и падение фронтенда. Лечится двумя командами (в этом стенде их делает entrypoint
при каждом старте):

```bash
docker exec superset_412 superset db upgrade   # схема
docker exec superset_412 superset init         # роли и права (без него — 403 в SQL Lab)
```

Перед этим стоит скопировать файл метаданных: `cp superset_home/superset.db superset.db.pre-4.1.2`.

## Грабли, на которые уже наступили

| Симптом | Причина | Решение |
|---|---|---|
| 500 на всех страницах, `no such column: slices.catalog_perm` | метаданные старой версии не мигрированы | `superset db upgrade` (entrypoint делает при старте) |
| SQL Lab: 403 и `TypeError: can't access property 2, r is undefined` | не выполнен `superset init` — роли без новых прав | `superset init` (тоже в entrypoint) |
| `No module named 'psycopg2'` при подключении к PostgreSQL | в голом образе 4.1.2 нет ни одного драйвера | драйверы базовой поставки уже в этом образе; см. `add-plugin.sh` |
| `unable to open database file` при старте | каталог `superset_home` создан docker'ом как root, а Superset работает под uid 1000 | `mkdir -p superset_home && chmod 777 superset_home` (делает `up.sh`); entrypoint сообщает об этом прямо |
| «Custom SQL fields cannot contain sub-queries» в таблицах | русские имена колонок не парсятся sqlglot в raw-режиме | `ALLOW_ADHOC_SUBQUERY: True` (уже включён) |
| Драйвер «поставлен», но Superset его не видит | пакет ушёл в другой интерпретатор, чем тот, из которого запущен Superset | `add-plugin.sh` ставит в `sys.executable` контейнера и проверяет импорт |
| `Refusing to start due to insecure SECRET_KEY` (CLI) | не задан `SUPERSET_SECRET_KEY` | заполнить `.env` (в образе есть проверка) |

## Метаданные в PostgreSQL (опционально)

1. Раскомментировать сервис `meta-db` в `docker-compose.yml` (версию образа фиксировать:
   `postgres:16-alpine`, а не `postgres:alpine` — иначе новый мажор не стартует на данных,
   созданных предыдущим).
2. В `.env` заполнить `SQLALCHEMY_DATABASE_URI`.
3. `bash scripts/rebuild.sh`.

## Что проверено на этом стенде

* Стенд поднимается с нуля: `db upgrade` по всем миграциям, `init`, создание админа,
  `/health` = 200; версия (через `importlib.metadata` в контейнере) — **4.1.2**.
* Интерпретатор Superset: `/usr/local/bin/python` (системный), драйверы там же:
  `clickhouse-connect 1.9.0`, `psycopg2-binary 2.9.13` — импортируются.
* `add-plugin.sh installed` показывает интерпретатор и драйверы (детект работает на 4.1.2,
  где нет ни `uv`, ни venv).
* Реальные запросы через Superset: ClickHouse (`stg.decl_declaration` → 25 680 строк) и
  PostgreSQL (`select 1`) — подключения создавались, проверялись и удалялись через API стенда.
* `HTML_SANITIZATION` + расширенная схема (svg/style в `tagNames`), `ENABLE_TEMPLATE_PROCESSING`,
  `ALLOW_ADHOC_SUBQUERY` применяются (проверено через `app.config`).
* Стенд 4.1.2 на :8082 и стенд 6.1.0 на :8081 работали одновременно, не мешая друг другу.
