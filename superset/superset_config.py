# =============================================================================
# Конфиг стенда superset-latest (Superset 6.1.0), подключается через
# SUPERSET_CONFIG_PATH=/app/superset_config.py
# =============================================================================
import os


def _env(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


# --- секрет подписи сессий ---------------------------------------------------
SECRET_KEY = _env("SUPERSET_SECRET_KEY", "local-superset-latest-change-me")
SUPERSET_SECRET_KEY = SECRET_KEY

# --- метаданные --------------------------------------------------------------
# По умолчанию SQLite в ./superset_home (смонтирован с хоста) — удобно для стенда.
# Для PostgreSQL: SQLALCHEMY_DATABASE_URI в .env (драйвер psycopg2 уже в образе).
_uri = _env("SQLALCHEMY_DATABASE_URI")
SQLALCHEMY_DATABASE_URI = _uri or "sqlite:////app/superset_home/superset.db?check_same_thread=false"

# --- локальный стенд ---------------------------------------------------------
ENABLE_PROXY_FIX = True
TALISMAN_ENABLED = False               # http без сертификата, CSP не навязываем
PREVENT_UNSAFE_DB_CONNECTIONS = False  # разрешаем любые строки подключения (локально)

# =============================================================================
# Handlebars-чарты: разрешить вёрстку и SVG.
# HTML шаблона рендерится через SafeMarkdown (rehype-sanitize); со схемой по
# умолчанию вырезаются class, style, data-*, тег <style> и все SVG-элементы —
# отчёт превращается в «голый HTML». Ниже разрешаем ровно необходимое,
# script/iframe/on*-атрибуты по-прежнему вырезаются.
# =============================================================================
HTML_SANITIZATION = True
HTML_SANITIZATION_SCHEMA_EXTENSIONS: dict = {
    "tagNames": [
        "style",
        "svg", "g", "path", "title", "text", "tspan",
        "circle", "rect", "line", "polygon", "polyline",
    ],
    "attributes": {
        "*": ["className", "style", "title", "data-*",
              "colspan", "rowspan", "height", "width", "role", "aria-label"],
        "svg": ["viewBox", "viewbox", "preserveAspectRatio", "preserveaspectratio",
                "xmlns", "width", "height", "aria-label", "role"],
        "path": ["d", "fill", "stroke", "stroke-width", "strokeWidth",
                 "fill-rule", "fillRule", "transform", "opacity", "className"],
        "g": ["transform", "fill", "stroke", "stroke-width", "opacity", "className"],
        "text": ["x", "y", "dx", "dy", "font-size", "fontSize", "text-anchor",
                 "textAnchor", "fill", "className"],
        "circle": ["cx", "cy", "r", "fill", "stroke", "stroke-width"],
        "style": [],
    },
}

# Jinja в SQL датасетов: нужна, чтобы чарт видел границы фильтра (from_dttm/to_dttm)
ENABLE_TEMPLATE_PROCESSING = True

FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,
    # Raw-режим таблиц: в 4.x+ имена колонок валидируются sqlglot, и русские имена
    # (с пробелами, префиксом --, запятыми) он не парсит — чарт падает с
    # «Custom SQL fields cannot contain sub-queries». Флаг снимает эту проверку;
    # на стенде с кириллическими датасетами он нужен.
    "ALLOW_ADHOC_SUBQUERY": True,
}
