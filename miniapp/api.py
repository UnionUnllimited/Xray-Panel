"""JSON-API мини-аппа на aiohttp-сервере бота (127.0.0.1:8081).

Наружу nginx публикует только префикс /miniapp/ — служебные /api/* бота
остаются недоступны. Каждый запрос подписан Telegram: заголовок
``Authorization: tma <initData>`` проверяется HMAC с токеном бота
(https://core.telegram.org/bots/webapps#validating-data-received-via-the-mini-app).

Логику не дублируем: тарифы, оплата, триал, промокоды и рефералы идут через
те же функции, что и в боте. Функции из main.py приходят через ``deps``
(прямой импорт main.py дал бы цикл).
"""
from __future__ import annotations

import asyncio
import json
import os
import time
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Optional

import httpx
from aiohttp import web
from aiogram.types import LabeledPrice
from aiogram.utils.web_app import safe_parse_webapp_init_data
from loguru import logger

import db_helpers
from app_config import app_conf
from payment_methods import PAYMENT_METHOD_LABELS, get_ordered_payment_methods
from remnawave_manager import remnawave_manager_instance
from subscription_manager import grant_subscription

PUBLIC_DIR = (Path(__file__).resolve().parent / 'public').resolve()
PREFIX = '/miniapp'

# Подпись initData живёт сутки: мини-апп открывают и держат открытым, но
# украденная строка не должна работать вечно.
INIT_DATA_MAX_AGE = 24 * 3600

# Методы, которые мини-апп умеет оплачивать (manual/promo — не оплата тарифа).
MINIAPP_METHODS = ('tgstar', 'yookassa', 'platega', 'wata', 'yoomoney', 'cryptobot')
WILDCARD_METHODS = ('both', 'all', None, '')
TARIFF_CHANGE_WINDOW_DAYS = 7

# Не больше 5 счетов за 5 минут на человека: счёт создаёт запись платежа и
# ходит в API кассы, а кнопку в интерфейсе можно нажать сколько угодно раз.
_PAY_LIMIT, _PAY_WINDOW = 5, 300
_pay_hits: dict[int, deque] = defaultdict(deque)

deps = SimpleNamespace()


class ApiError(Exception):
    def __init__(self, status: int, message: str, code: str = ''):
        super().__init__(message)
        self.status, self.message, self.code = status, message, code


def _json(data: dict, status: int = 200) -> web.Response:
    return web.json_response(data, status=status, headers={'Cache-Control': 'no-store'})


def _setting(key: str, default: str = '') -> str:
    val = app_conf.get(key, default)
    return default if val is None else str(val)


def _flag(key: str, default: str = '0') -> bool:
    return _setting(key, default).strip().lower() in ('1', 'true', 'yes', 'on')


def _int(val: Any, default: int = 0) -> int:
    try:
        return int(float(val))
    except (TypeError, ValueError):
        return default


def _parse_dt(raw: Any) -> Optional[datetime]:
    if not raw:
        return None
    if isinstance(raw, datetime):
        dt = raw
    else:
        try:
            dt = datetime.fromisoformat(str(raw).replace('Z', '+00:00'))
        except ValueError:
            return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


# ───────────────────────────── Авторизация ─────────────────────────────

async def _auth(request: web.Request) -> dict:
    """Проверяет initData и возвращает {'id', 'tg', 'db'}; заводит пользователя в базе."""
    header = request.headers.get('Authorization', '')
    if not header.startswith('tma '):
        raise ApiError(401, 'Откройте приложение из Telegram')
    bot = deps.get_bot()
    try:
        data = safe_parse_webapp_init_data(bot.token, header[4:])
    except ValueError:
        raise ApiError(401, 'Подпись Telegram не прошла проверку. Откройте приложение заново')
    auth_date = data.auth_date
    if auth_date.tzinfo is None:
        auth_date = auth_date.replace(tzinfo=timezone.utc)
    if (datetime.now(timezone.utc) - auth_date).total_seconds() > INIT_DATA_MAX_AGE:
        raise ApiError(401, 'Сессия устарела. Закройте и откройте приложение заново')
    tg_user = data.user
    if not tg_user:
        raise ApiError(401, 'Telegram не передал пользователя')
    user_id = int(tg_user.id)
    # Как show_main_menu: человек, открывший мини-апп по прямой ссылке, тоже становится клиентом.
    await db_helpers.add_user(user_id, (tg_user.first_name or '')[:32], tg_user.username or None)
    row = await db_helpers.get_user(user_id)
    db_user = dict(row) if row else {}
    if _int(db_user.get('is_blocked')) == 1:
        raise ApiError(403, 'Аккаунт заблокирован. Напишите в поддержку', 'blocked')
    return {'id': user_id, 'tg': tg_user, 'db': db_user}


def route(handler):
    async def wrapped(request: web.Request) -> web.Response:
        try:
            me = await _auth(request)
            return _json(await handler(request, me))
        except ApiError as e:
            return _json({'ok': False, 'error': e.message, 'code': e.code}, e.status)
        except Exception as e:  # noqa: BLE001 — ответ клиенту без трейсбека, сам трейсбек в лог
            logger.error(f"[MINIAPP] {request.method} {request.path}: {type(e).__name__}: {e}", exc_info=True)
            return _json({'ok': False, 'error': 'Внутренняя ошибка. Попробуйте позже'}, 500)
    return wrapped


async def _read_json(request: web.Request) -> dict:
    try:
        body = await request.json()
    except Exception:
        raise ApiError(400, 'Некорректный запрос')
    if not isinstance(body, dict):
        raise ApiError(400, 'Некорректный запрос')
    return body


# ───────────────────────────── Подписка ─────────────────────────────

def _sub_url(db_user: dict) -> str:
    uuid = db_user.get('xui_client_uuid') or ''
    base = _setting('sub_page_url').rstrip('/')
    return f"{base}/sub/{uuid}" if (base and uuid) else ''


async def _traffic(db_user: dict) -> Optional[dict]:
    short_uuid = db_user.get('remnawave_short_uuid')
    if not short_uuid:
        return None
    try:
        info = await asyncio.wait_for(remnawave_manager_instance.get_subscription_info(short_uuid), timeout=6)
    except Exception as e:  # панель недоступна — экран всё равно должен открыться
        logger.warning(f"[MINIAPP] трафик {short_uuid}: {type(e).__name__}: {e}")
        return None
    if not info:
        return None
    return {'used': _int(info.get('trafficUsedBytes')), 'limit': _int(info.get('trafficLimitBytes'))}


def _subscription(db_user: dict) -> Optional[dict]:
    end = _parse_dt(db_user.get('subscription_end_date'))
    if not end or not db_user.get('xui_client_uuid'):
        return None
    now = datetime.now(timezone.utc)
    seconds = (end - now).total_seconds()
    return {
        'active': seconds > 0,
        'end_at': end.isoformat(),
        'days_left': max(0, int(seconds // 86400)),
        'hours_left': max(0, int(seconds // 3600)),
        'limit_ip': _int(db_user.get('limit_ip')),
        'sub_url': _sub_url(db_user),
    }


def _limit_rules(db_user: dict) -> dict:
    """Какие лимиты устройств можно купить — то же правило, что в кабинете и боте.

    Первая покупка — любой; за 7 дней до конца подписки и после неё — свой или
    больший; раньше — только свой. 0 = без лимита, он «выше» любого числа.
    """
    existing = _int(db_user.get('limit_ip'))
    end = _parse_dt(db_user.get('subscription_end_date'))
    first = (end is None) or existing <= 0
    days_until_end = (end - datetime.now(timezone.utc)).total_seconds() / 86400 if end else None
    window = (not first) and (days_until_end is None or days_until_end <= TARIFF_CHANGE_WINDOW_DAYS)
    mode = 'any' if first else ('same_or_higher' if window else 'same')
    return {'mode': mode, 'current': existing, 'window_days': TARIFF_CHANGE_WINDOW_DAYS}


def _limit_allowed(rules: dict, t_limit: int) -> bool:
    mode, cur = rules['mode'], rules['current']
    if mode == 'any':
        return True
    if mode == 'same':
        return t_limit == cur
    if cur <= 0:
        return t_limit <= 0
    return t_limit <= 0 or t_limit >= cur


def _trial_state(db_user: dict, sub: Optional[dict]) -> dict:
    days = _int(_setting('trial_days', '3'))
    available = days > 0 and not _int(db_user.get('is_trial_used')) and not (sub and sub['active'])
    return {'available': available, 'days': days}


def _channel_link(identifier: str) -> str:
    ident = (identifier or '').strip()
    if ident.startswith('https://'):
        return ident
    name = ident.lstrip('@')
    return f"https://t.me/{name}" if name and not name.lstrip('-').isdigit() else ''


def _apps() -> list[dict]:
    """Клиенты по платформам из тех же ссылок, что в боте (app_link_*)."""
    spec = [
        ('ios', 'iPhone и iPad', [('Happ', 'app_link_ios'), ('Happ (вне РФ)', 'app_link_ios_global'), ('V2RayTun', 'app_link_v2raytun_ios'), ('Hiddify', 'app_link_hiddify_ios')]),
        ('android', 'Android', [('Happ', 'app_link_android'), ('Happ (APK)', 'app_link_android_apk'), ('V2RayTun', 'app_link_v2raytun_android'), ('Hiddify', 'app_link_hiddify_android')]),
        ('windows', 'Windows', [('Happ', 'app_link_windows'), ('V2RayTun', 'app_link_v2raytun_windows')]),
        ('mac', 'macOS', [('Happ', 'app_link_mac'), ('V2RayTun', 'app_link_v2raytun_mac')]),
        ('linux', 'Linux', [('Happ', 'app_link_linux')]),
    ]
    out = []
    for pid, name, items in spec:
        links = [{'name': n, 'url': _setting(k).strip()} for n, k in items if _setting(k).strip().startswith('http')]
        if links:
            out.append({'id': pid, 'name': name, 'apps': links})
    return out


async def _bot_username() -> str:
    name = _setting('bot_username').strip().lstrip('@')
    if name:
        return name
    try:
        return (await deps.get_bot().get_me()).username or ''
    except Exception:
        return ''


async def api_me(request: web.Request, me: dict) -> dict:
    db_user = me['db']
    sub = _subscription(db_user)
    if sub:
        sub['traffic'] = await _traffic(db_user)
    tg = me['tg']
    channel_on = _flag('channel_subscription_enabled')
    return {
        'ok': True,
        'user': {'id': me['id'], 'first_name': tg.first_name, 'last_name': tg.last_name,
                 'username': tg.username, 'photo_url': tg.photo_url},
        'project': {
            'name': _setting('project_name').strip() or 'Подписка',
            'support_url': _setting('support_link').strip() or _setting('support_url').strip(),
            'bot_username': await _bot_username(),
            'sub_page_url': _setting('sub_page_url').rstrip('/'),
        },
        'subscription': sub,
        'trial': {**_trial_state(db_user, sub),
                  'channel': _channel_link(_setting('channel_subscription_username')) if channel_on else ''},
        'features': {
            'promo': _flag('show_payment_promo_code', '1'),
            'devices': _flag('hwid_limit_enabled') and bool(db_user.get('xui_client_uuid')),
        },
        'apps': _apps(),
    }


# ───────────────────────────── Тарифы и оплата ─────────────────────────────

def _available_methods() -> list[str]:
    return [m for m in get_ordered_payment_methods('bot') if m in MINIAPP_METHODS]


def _tariff_json(t: dict) -> dict:
    return {
        'id': t['id'], 'name': t.get('name') or '', 'days': _int(t.get('days')),
        'price': float(t.get('price') or 0), 'currency': t.get('currency') or 'RUB',
        'limit_ip': _int(t.get('limit_ip')), 'traffic_gb': _int(t.get('traffic_gb')),
        'description': (t.get('description') or '').strip(), 'method': t.get('payment_method') or '',
    }


async def api_tariffs(request: web.Request, me: dict) -> dict:
    methods = _available_methods()
    rules = _limit_rules(me['db'])
    out = []
    for row in await db_helpers.get_active_tariffs():
        t = dict(row)
        pm = t.get('payment_method')
        targets = methods if pm in WILDCARD_METHODS else [pm] if pm in methods else []
        for m in targets:
            item = _tariff_json(t)
            item['method'] = m
            item['allowed'] = _limit_allowed(rules, item['limit_ip'])
            if m == 'tgstar':
                from src.pay import rub_to_stars
                item['stars'] = rub_to_stars(item['price'], app_conf)
            out.append(item)
    return {
        'ok': True,
        'methods': [{'id': m, 'name': PAYMENT_METHOD_LABELS.get(m, m)} for m in methods],
        'tariffs': out,
        'rules': rules,
    }


def _rate_limited(user_id: int) -> bool:
    q, now = _pay_hits[user_id], time.monotonic()
    while q and now - q[0] > _PAY_WINDOW:
        q.popleft()
    if len(q) >= _PAY_LIMIT:
        return True
    q.append(now)
    return False


async def _return_url() -> str:
    name = await _bot_username()
    return f"https://t.me/{name}" if name else 'https://t.me'


async def _pay_tgstar(tariff: dict, user_id: int) -> dict:
    # Тот же payload, что у кнопки в боте: оплату примет process_tgstar_payment.
    from src.pay import rub_to_stars
    stars = rub_to_stars(float(tariff['price']), app_conf)
    rub = float(tariff['price'])
    rub_str = int(rub) if rub == int(rub) else f"{rub:.2f}"
    desc = (tariff.get('description') or tariff.get('name') or 'Оплата тарифа').strip()
    link = await deps.get_bot().create_invoice_link(
        title=(tariff.get('name') or 'Подписка')[:32],
        description=f"{desc}\n\n{rub_str} ₽ ≈ {stars} ⭐"[:255],
        payload=f"tgstar_{tariff['id']}_{user_id}",
        provider_token=_setting('tgstar_provider_token') or '',
        currency='XTR',
        prices=[LabeledPrice(label=(tariff.get('name') or 'Подписка')[:32], amount=stars)],
    )
    return {'kind': 'invoice', 'url': link}


async def _pay_cryptobot(tariff: dict, user_id: int) -> Optional[str]:
    # Повторяет cq_renew_tariff_cryptobot: оплату примет вебхук invoice_paid.
    token = _setting('cryptobot_token').strip()
    if not token:
        return None
    from src.pay import cryptobot_fiat_invoice_body
    payload = f"{user_id}|{tariff['id']}|{tariff['days']}|{tariff.get('limit_ip', 0)}"
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.post('https://pay.crypt.bot/api/createInvoice',
                              headers={'Crypto-Pay-API-Token': token},
                              json={**cryptobot_fiat_invoice_body(tariff['price']), 'payload': payload, 'allow_comments': False})
        r.raise_for_status()
        data = r.json()
    if not data.get('ok'):
        raise RuntimeError(f"CryptoBot: {data.get('error')}")
    inv = data['result']
    meta = {'telegram_user_id': user_id, 'subscription_days': tariff['days'], 'price': tariff['price'],
            'limit_ip': tariff.get('limit_ip', 0), 'tariff_id': tariff['id'], 'payment_method': 'CryptoBot',
            'payload': payload, 'source': 'miniapp'}
    await db_helpers.add_payment(payment_id=f"CRYPTO_{inv['invoice_id']}", telegram_id=user_id,
                                 amount=tariff['price'], currency='RUB',
                                 metadata_json=json.dumps(meta, ensure_ascii=False))
    return inv.get('mini_app_invoice_url') or inv.get('bot_invoice_url') or inv['pay_url']


async def _pay_url(method: str, tariff: dict, user_id: int) -> Optional[str]:
    from src.pay import (create_platega_payment_shared, create_wata_payment_shared,
                         create_yookassa_payment_shared, create_yoomoney_quickpay)
    amount = float(tariff['price'])
    currency = tariff.get('currency') or 'RUB'
    return_url = await _return_url()
    result = None
    if method == 'yookassa':
        shop_id, secret = _setting('yookassa_shop_id').strip(), _setting('yookassa_secret_key').strip()
        if not (shop_id and secret):
            return None
        result = await create_yookassa_payment_shared(
            shop_id=shop_id, secret_key=secret, amount=amount, currency=currency, tariff=tariff,
            user_id=user_id, return_url=return_url, sbp_only=_flag('yookassa_sbp_only'))
    elif method == 'platega':
        merchant, secret = _setting('platega_merchant_id').strip(), _setting('platega_api_secret').strip()
        if not (merchant and secret):
            return None
        result = await create_platega_payment_shared(
            merchant_id=merchant, api_secret=secret, amount=amount, tariff=tariff,
            user_id=user_id, return_url=return_url)
    elif method == 'wata':
        token = _setting('wata_access_token').strip() or os.getenv('WATA_ACCESS_TOKEN', '')
        if not token:
            return None
        terminal = _setting('wata_terminal_public_id').strip() or os.getenv('WATA_TERMINAL_PUBLIC_ID', '')
        result = await create_wata_payment_shared(
            token, amount=amount, tariff=tariff, user_id=user_id, return_url=return_url,
            currency=currency, terminal_public_id=terminal)
    elif method == 'yoomoney':
        account = _setting('yoomoney_account').strip()
        if not account:
            return None
        pid = f"YOOMONEY_{int(time.time())}_{user_id}_{tariff['id']}"
        meta = {'amount': amount, 'currency': currency, 'payment_id': pid, 'user_id': user_id,
                'telegram_user_id': user_id, 'tariff_id': tariff['id'], 'days': tariff['days'],
                'subscription_days': tariff['days'], 'limit_ip': tariff.get('limit_ip', 0),
                'description': f"Подписка: {tariff.get('name', '')} на {tariff['days']} дней", 'source': 'miniapp'}
        url = await create_yoomoney_quickpay(account=account, telegram_id=user_id, payment_id=pid, amount=amount,
                                             currency=currency, target_text=f"Подписка {tariff.get('name', '')}".strip(),
                                             metadata=meta)
        return url or None
    elif method == 'cryptobot':
        return await _pay_cryptobot(tariff, user_id)
    return result[1] if result else None


async def api_pay(request: web.Request, me: dict) -> dict:
    body = await _read_json(request)
    method = str(body.get('method') or '')
    tariff_id = _int(body.get('tariff_id'), -1)
    if method not in _available_methods():
        raise ApiError(400, 'Этот способ оплаты сейчас недоступен')
    row = await db_helpers.get_tariff_by_id(tariff_id)
    tariff = dict(row) if row else None
    if not tariff or not _int(tariff.get('is_active'), 1):
        raise ApiError(404, 'Тариф не найден')
    if tariff.get('payment_method') not in WILDCARD_METHODS and tariff.get('payment_method') != method:
        raise ApiError(400, 'Тариф не продаётся этим способом')
    rules = _limit_rules(me['db'])
    if not _limit_allowed(rules, _int(tariff.get('limit_ip'))):
        raise ApiError(403, 'Сменить лимит устройств можно за 7 дней до конца подписки или после неё. Понизить — через поддержку'
                       if rules['mode'] == 'same' else 'Понизить лимит устройств нельзя — только через поддержку', 'limit')
    if _rate_limited(me['id']):
        raise ApiError(429, 'Слишком много попыток. Подождите пару минут')
    if method == 'tgstar':
        return {'ok': True, **(await _pay_tgstar(tariff, me['id']))}
    url = await _pay_url(method, tariff, me['id'])
    if not url:
        raise ApiError(503, 'Не удалось создать платёж. Попробуйте другой способ или позже')
    logger.info(f"[MINIAPP] счёт {method} tariff={tariff_id} user={me['id']}")
    return {'ok': True, 'kind': 'url', 'url': url}


# ───────────────────────────── Триал, промокод ─────────────────────────────

async def api_trial(request: web.Request, me: dict) -> dict:
    user_id = me['id']
    if not deps.trial_enabled():
        raise ApiError(400, 'Пробный период отключён')
    if _flag('channel_subscription_enabled'):
        channel = _setting('channel_subscription_username').strip()
        if channel:
            from src.channel_subscription import get_channel_checker
            if not await get_channel_checker(deps.get_bot()).check_subscription(user_id, channel):
                raise ApiError(403, 'Подпишитесь на канал — и пробный период станет доступен', 'channel')
    # Тот же замок, что у /start в боте: два нажатия не выдадут два триала.
    lock = deps.trial_locks.setdefault(user_id, asyncio.Lock())
    async with lock:
        row = await db_helpers.get_user(user_id)
        user = dict(row) if row else {}
        if _int(user.get('is_trial_used')):
            raise ApiError(409, 'Пробный период уже использован')
        if await db_helpers.get_active_subscription(user_id):
            raise ApiError(409, 'Подписка уже активна')
        days = _int(_setting('trial_days', '3'))
        limit_ip = _int(_setting('trial_limit_ip', '1'), 1)
        result = await grant_subscription(user_id, days, is_trial=True, limit_ip=limit_ip)
    if not result:
        raise ApiError(500, 'Не удалось выдать пробный период. Напишите в поддержку')
    logger.info(f"[MINIAPP] триал {days} дн. user={user_id}")
    return {'ok': True, 'days': days, 'end_at': _parse_dt(result.get('expiry_date')).isoformat() if result.get('expiry_date') else None}


_PROMO_ERRORS = {
    'not_found': 'Такого промокода нет',
    'inactive': 'Промокод больше не действует',
    'limit_reached': 'Промокод больше не действует',
    'already_used_by_user': 'Вы уже активировали этот промокод',
}


async def api_promo(request: web.Request, me: dict) -> dict:
    if not _flag('show_payment_promo_code', '1'):
        raise ApiError(400, 'Промокоды сейчас не принимаются')
    code = str((await _read_json(request)).get('code') or '').strip().upper()
    if not code or len(code) > 64:
        raise ApiError(400, 'Введите промокод')
    if _rate_limited(me['id']):
        raise ApiError(429, 'Слишком много попыток. Подождите пару минут')
    redeem = await db_helpers.redeem_promo_code(code, me['id'])
    if not redeem.get('ok'):
        raise ApiError(400, _PROMO_ERRORS.get(redeem.get('error'), 'Не удалось активировать промокод'))
    days = _int(redeem.get('days')) or _int(_setting('promo_code_subscription_days', '30'), 30)
    limit_ip = await deps.resolve_limit_ip(me['id'])
    result = await grant_subscription(me['id'], days, is_trial=False, limit_ip=limit_ip, reset_traffic_on_renewal=False)
    if not result:
        raise ApiError(500, 'Промокод принят, но подписку продлить не удалось. Напишите в поддержку')
    return {'ok': True, 'days': days}


# ───────────────────────────── Друзья ─────────────────────────────

def _partner_visible(db_user: dict) -> bool:
    own = db_user.get('show_partner_program_button')
    if own in ('1', 1):
        return True
    if own in ('0', 0):
        return False
    return _flag('show_partner_program_button', '1')


async def api_friends(request: web.Request, me: dict) -> dict:
    user_id = me['id']
    name = await _bot_username()
    referrals = await db_helpers.get_referrals(user_id)
    today = await db_helpers.get_referrals_count_today(user_id)
    per_day = _int(_setting('referral_limit_per_day', '3'), 3)
    out = {
        'ok': True,
        'link': f"https://t.me/{name}?start={user_id}" if name else '',
        'invited': len(referrals),
        'today': today, 'per_day': per_day,
        'join_days': _int(_setting('ref_bonus_on_join_days', '0')),
        'payment_days': _int(_setting('ref_bonus_on_payment_days', '0')),
        'partner': None,
    }
    if _partner_visible(me['db']):
        code = await deps.ensure_partner_code(user_id)
        stats = await deps.partner_stats(user_id)
        out['partner'] = {
            'link': f"https://t.me/{name}?start=par_{code}" if (name and code) else '',
            'balance': stats.get('balance', 0.0), 'invited': stats.get('ref_count', 0),
            'payments': stats.get('pay_count', 0),
            'percent': await db_helpers.get_partner_percent(user_id),
            'min_withdraw': _int(_setting('partner_min_withdraw_rub', '0')),
        }
    return out


# ───────────────────────────── Устройства, платежи ─────────────────────────────

def _device_uuid(db_user: dict) -> str:
    return db_user.get('xui_client_uuid') or db_user.get('remnawave_short_uuid') or ''


async def api_devices(request: web.Request, me: dict) -> dict:
    uuid = _device_uuid(me['db'])
    if not (_flag('hwid_limit_enabled') and uuid):
        return {'ok': True, 'enabled': False, 'items': []}
    items = []
    for d in await deps.devices_fetch(uuid):
        items.append({
            'hwid': d.get('hwid') or '',
            'name': d.get('custom_name') or d.get('model') or d.get('os') or 'Устройство',
            'os': ' '.join(x for x in (d.get('os'), d.get('os_version')) if x),
            'app': d.get('app') or '',
            'last_seen': d.get('access_time') or d.get('created_at') or '',
        })
    return {'ok': True, 'enabled': True, 'limit': _int(me['db'].get('limit_ip')), 'items': items}


async def api_devices_delete(request: web.Request, me: dict) -> dict:
    hwid = str((await _read_json(request)).get('hwid') or '').strip()
    uuid = _device_uuid(me['db'])
    if not (hwid and uuid and _flag('hwid_limit_enabled')):
        raise ApiError(400, 'Устройство не найдено')
    # Удаляем только своё: hwid должен быть в списке устройств этого клиента.
    if hwid not in {d.get('hwid') for d in await deps.devices_fetch(uuid)}:
        raise ApiError(404, 'Устройство не найдено')
    if not await deps.devices_delete(uuid, hwid):
        raise ApiError(502, 'Не удалось отвязать устройство. Попробуйте позже')
    return {'ok': True}


def _method_from_id(pid: str, meta: dict) -> str:
    p = (pid or '').upper()
    for prefix, name in (('TGSTAR', 'Telegram Stars'), ('CRYPTO', 'CryptoBot'), ('PLATEGA', 'Platega'),
                         ('WATA', 'Wata'), ('YOOMONEY', 'YooMoney')):
        if p.startswith(prefix):
            return name
    return str(meta.get('payment_method') or 'YooKassa')


async def api_payments(request: web.Request, me: dict) -> dict:
    items = []
    for pid, _uid, amount, currency, status, created_at, meta_raw in (await db_helpers.get_user_payments(me['id']))[:30]:
        try:
            meta = json.loads(meta_raw) if meta_raw else {}
        except (TypeError, ValueError):
            meta = {}
        # Идентификатор платежа клиенту не отдаём: по нему можно подделать уведомление кассы.
        items.append({
            'amount': float(amount or 0), 'currency': currency or 'RUB', 'status': status,
            'created_at': created_at, 'method': _method_from_id(pid, meta),
            'days': _int(meta.get('subscription_days') or meta.get('days')),
            'kind': meta.get('payment_type') or 'subscription',
        })
    return {'ok': True, 'items': items}


# ───────────────────────────── Статика ─────────────────────────────

_TYPES = {'.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.html': 'text/html',
          '.png': 'image/png', '.webp': 'image/webp', '.json': 'application/json'}


async def static_file(request: web.Request) -> web.StreamResponse:
    tail = request.match_info.get('tail') or 'index.html'
    path = (PUBLIC_DIR / tail).resolve()
    if PUBLIC_DIR not in path.parents or not path.is_file():
        raise web.HTTPNotFound()
    # no-cache = «проверь перед использованием»: обновление бота сразу доходит до клиентов,
    # а неизменённые файлы отдаются как 304 по Last-Modified.
    return web.FileResponse(path, headers={
        'Cache-Control': 'no-cache',
        'Content-Type': _TYPES.get(path.suffix, 'application/octet-stream'),
        'X-Content-Type-Options': 'nosniff',
    })


async def _index_redirect(request: web.Request) -> web.Response:
    raise web.HTTPFound(f"{PREFIX}/")


def setup_miniapp(app: web.Application, **kwargs) -> None:
    """Регистрирует /miniapp/* на aiohttp-приложении бота.

    kwargs: get_bot, trial_enabled, trial_locks, resolve_limit_ip,
    ensure_partner_code, partner_stats, devices_fetch, devices_delete.
    """
    for k, v in kwargs.items():
        setattr(deps, k, v)
    r = app.router
    r.add_get(f'{PREFIX}/api/me', route(api_me))
    r.add_get(f'{PREFIX}/api/tariffs', route(api_tariffs))
    r.add_post(f'{PREFIX}/api/pay', route(api_pay))
    r.add_post(f'{PREFIX}/api/trial', route(api_trial))
    r.add_post(f'{PREFIX}/api/promo', route(api_promo))
    r.add_get(f'{PREFIX}/api/friends', route(api_friends))
    r.add_get(f'{PREFIX}/api/devices', route(api_devices))
    r.add_post(f'{PREFIX}/api/devices/delete', route(api_devices_delete))
    r.add_get(f'{PREFIX}/api/payments', route(api_payments))
    r.add_get(PREFIX, _index_redirect)
    r.add_get(f'{PREFIX}/{{tail:.*}}', static_file)
    logger.info(f"[MINIAPP] маршруты {PREFIX}/ зарегистрированы, статика: {PUBLIC_DIR}")
