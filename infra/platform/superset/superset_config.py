import os


SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "change-this-superset-secret")
SQLALCHEMY_DATABASE_URI = os.environ.get(
    "SUPERSET_META_DB_URI",
    "sqlite:////app/superset_home/superset.db",
)

# Local single-container setup: keep caching in-process to avoid adding Redis.
CACHE_CONFIG = {
    "CACHE_TYPE": "SimpleCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
}
DATA_CACHE_CONFIG = CACHE_CONFIG
FILTER_STATE_CACHE_CONFIG = CACHE_CONFIG
EXPLORE_FORM_DATA_CACHE_CONFIG = CACHE_CONFIG

WTF_CSRF_TIME_LIMIT = None
