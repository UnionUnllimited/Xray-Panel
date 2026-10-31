"""Адрес мини-аппа для кнопок бота. Лёгкий модуль: импортируется из keyboards и main."""
from urllib.parse import urlparse

from app_config import app_conf

PREFIX = '/miniapp'
# Заглушки из шаблона настроек: с ними кнопка вела бы на чужой домен.
_PLACEHOLDER_HOSTS = {'bot.domain.ru', 'domain.ru', 'example.com'}


def miniapp_url() -> str:
    """HTTPS-адрес мини-аппа или '' — тогда бот кнопок мини-аппа не показывает.

    По умолчанию это {connect_page_url}/miniapp/ — тот же домен, что у вебхуков.
    Telegram открывает WebApp только по https.
    """
    if str(app_conf.get('miniapp_enabled', '1')).strip().lower() not in ('1', 'true', 'yes', 'on'):
        return ''
    url = str(app_conf.get('miniapp_url', '') or '').strip()
    if not url:
        base = str(app_conf.get('connect_page_url', '') or '').strip().rstrip('/')
        if not base:
            return ''
        url = f"{base}{PREFIX}/"
    parsed = urlparse(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.hostname in _PLACEHOLDER_HOSTS:
        return ''
    return url
