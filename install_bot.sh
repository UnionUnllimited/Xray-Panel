#!/bin/bash
set -e

# Проверка запуска из /root/bot/
if [[ "$PWD" != "/root/bot" ]]; then
  echo "Скрипт должен запускаться из /root/bot/! Текущая папка: $PWD"
  exit 1
fi

# Ждём освобождения dpkg/apt lock (unattended-upgrades и др.)
wait_apt_lock() {
  local i=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
    if [ $i -eq 0 ]; then
      echo "Ожидание освобождения apt lock (фоновые обновления)..."
    fi
    sleep 3
    i=$((i+1))
    if [ $i -ge 40 ]; then
      echo "apt lock занят слишком долго, завершаем unattended-upgrades..."
      systemctl stop unattended-upgrades 2>/dev/null || true
      killall unattended-upgrades 2>/dev/null || true
      sleep 2
      break
    fi
  done
}

# Установка Python, pip и sqlite3
wait_apt_lock
apt update
wait_apt_lock
apt install -y python3 python3-venv python3-pip sqlite3

# Установка из git: базы vpn_bot.db ещё нет (в репозитории её не храним).
# Без неё скрипт ниже молча пропустил бы запись домена, секретного пути и
# токена — и nginx смотрел бы на один путь, а админка на другой. Создаём
# таблицу настроек той же схемой, что db_helpers.init_db(); остальное бот
# засеет сам при первом старте (INSERT OR IGNORE — наши значения останутся).
if [ ! -f "/root/bot/vpn_bot.db" ]; then
  sqlite3 /root/bot/vpn_bot.db \
    "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT, description TEXT);"
  echo "Создана новая база /root/bot/vpn_bot.db"
fi

# Значение для SQL-литерала в одинарных кавычках: ' -> ''
sql_escape() { printf "%s" "${1//\'/\'\'}"; }

# Установка nginx, если не установлен
if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx не найден, устанавливаю..."
  apt install -y nginx
else
  echo "nginx уже установлен."
fi

# Установка certbot, если не установлен
if ! command -v certbot >/dev/null 2>&1; then
  echo "certbot не найден, устанавливаю..."
  apt install -y certbot
fi


# Перезапуск nginx для применения конфига (может быть нужен для certbot)
systemctl restart nginx

# ── Секретный путь веб-админки ────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Секретный путь веб-админки"
echo "  (используется в URL: https://домен/<путь>/)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ADMIN_PATH_CURRENT=""
if [ -f "/root/bot/vpn_bot.db" ]; then
  ADMIN_PATH_CURRENT=$(sqlite3 /root/bot/vpn_bot.db "SELECT value FROM settings WHERE key='admin_secret_path' LIMIT 1;" 2>/dev/null || true)
fi
ADMIN_PATH_DEFAULT="${ADMIN_PATH_CURRENT:-admin123}"

read -rp "  Введите секретный путь [по умолчанию: $ADMIN_PATH_DEFAULT]: " ADMIN_PATH_INPUT
ADMIN_SECRET_PATH="${ADMIN_PATH_INPUT:-$ADMIN_PATH_DEFAULT}"
# Убираем слэши по краям
ADMIN_SECRET_PATH="${ADMIN_SECRET_PATH#/}"
ADMIN_SECRET_PATH="${ADMIN_SECRET_PATH%/}"
echo "  Секретный путь: /$ADMIN_SECRET_PATH/"

# --- Получение SSL-сертификата через certbot ---
echo "\n=== Получение SSL-сертификата для nginx ==="
read -p "Введите ваш домен для SSL (например, example.com): " DOMAIN

# Проверка, что домен не пустой
if [ -z "$DOMAIN" ]; then
  echo "Домен не введён, пропускаю получение сертификата."
else
  # Остановить nginx, если запущен
  systemctl stop nginx || true

  # Получить сертификат через certbot
  certbot certonly --standalone -d "$DOMAIN"

  # Создать папку для сертификатов, если нет
  mkdir -p /root/cert/

  # Скопировать сертификаты
  if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /root/cert/fullchain.pem
    cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" /root/cert/privkey.pem
    echo "Сертификаты скопированы в /root/cert/"
  else
    echo "Сертификаты не найдены. Проверьте, что certbot успешно получил их."
  fi

# Копирование xuiweb.conf в конфиг nginx с подстановкой домена и секретного пути
sed "s/bot\.domain\.ru/$DOMAIN/g; s/admin123/$ADMIN_SECRET_PATH/g" service/xuiweb.conf > /etc/nginx/conf.d/xuiweb.conf

  # Прописываем домен и секретный путь в БД
  if [ -f "/root/bot/vpn_bot.db" ]; then
    sqlite3 /root/bot/vpn_bot.db \
      "INSERT INTO settings (key, value) VALUES ('connect_page_url', 'https://$DOMAIN')
       ON CONFLICT(key) DO UPDATE SET value = excluded.value;
       INSERT INTO settings (key, value) VALUES ('admin_secret_path', '$ADMIN_SECRET_PATH')
       ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
    echo "connect_page_url → https://$DOMAIN"
    echo "admin_secret_path → /$ADMIN_SECRET_PATH/"
  else
    echo "БД не найдена, пропускаю обновление настроек домена."
  fi

  # Запустить nginx обратно
  systemctl start nginx
fi

echo "\nУстановка зависимостей Python..."
# Создание venv для бота
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
pip install -r service/requirements.txt
deactivate

# Создание venv для web_admin
if [ ! -d "web_admin/venv" ]; then
  python3 -m venv web_admin/venv
fi
source web_admin/venv/bin/activate
pip install --upgrade pip
pip install -r service/requirements.txt
deactivate

# Создание venv для xuiweb
if [ ! -d "xuiweb/venv" ]; then
  python3 -m venv xuiweb/venv
fi
source xuiweb/venv/bin/activate
pip install --upgrade pip
pip install -r service/xuiweb.txt
deactivate

echo "\nУстановка завершена!"

# ── Настройка токена бота ──────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Настройка токена Telegram-бота"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BOT_TOKEN_SET=""
if [ -f "/root/bot/vpn_bot.db" ]; then
  BOT_TOKEN_SET=$(sqlite3 /root/bot/vpn_bot.db "SELECT value FROM settings WHERE key='bot_token' LIMIT 1;" 2>/dev/null || true)
fi

if [ -n "$BOT_TOKEN_SET" ]; then
  # Показываем замаскированный токен (первые 10 символов + ***)
  MASKED="${BOT_TOKEN_SET:0:10}***"
  echo "  Токен уже установлен: $MASKED"
  read -rp "  Изменить токен? [y/N]: " change_token
  if [[ "$change_token" =~ ^[Yy]$ ]]; then
    BOT_TOKEN_SET=""
  fi
fi

if [ -z "$BOT_TOKEN_SET" ]; then
  echo ""
  echo "  Получить токен можно у @BotFather в Telegram."
  read -rp "  Введите токен бота (или Enter чтобы пропустить): " BOT_TOKEN_INPUT
  if [ -n "$BOT_TOKEN_INPUT" ]; then
    if [ -f "/root/bot/vpn_bot.db" ]; then
      sqlite3 /root/bot/vpn_bot.db \
        "INSERT INTO settings (key, value) VALUES ('bot_token', '$BOT_TOKEN_INPUT')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
      echo "  Токен бота сохранён."
    else
      echo "  БД не найдена, токен не сохранён. Укажите его в веб-админке после запуска."
    fi
  else
    echo "  Пропущено. Укажите токен бота в веб-админке после запуска."
    echo "  ⚠️  Внимание: без токена сервис бота будет запущен, но работать не сможет"
    echo "      и может создавать лишнюю нагрузку на сервер."
  fi
fi

# ── Пароль веб-админки ────────────────────────────────────────────────────────
# В дистрибутиве пароль приезжал в готовой базе. На чистой базе его нет,
# поэтому задаём здесь: без пароля в админку не войти.
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Пароль веб-админки"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ADMIN_PWD_GENERATED=""
ADMIN_PWD_SET=$(sqlite3 /root/bot/vpn_bot.db "SELECT value FROM settings WHERE key='admin_web_password' LIMIT 1;" 2>/dev/null || true)
if [ -n "$ADMIN_PWD_SET" ]; then
  read -rp "  Пароль уже задан. Сменить? [y/N]: " change_pwd
  [[ "$change_pwd" =~ ^[Yy]$ ]] && ADMIN_PWD_SET=""
fi
if [ -z "$ADMIN_PWD_SET" ]; then
  read -rsp "  Введите пароль (Enter — сгенерировать): " ADMIN_PWD_INPUT; echo
  if [ -z "$ADMIN_PWD_INPUT" ]; then
    ADMIN_PWD_INPUT=$(python3 -c 'import secrets; print(secrets.token_urlsafe(12))')
    ADMIN_PWD_GENERATED="$ADMIN_PWD_INPUT"
  fi
  sqlite3 /root/bot/vpn_bot.db \
    "INSERT INTO settings (key, value) VALUES ('admin_web_password', '$(sql_escape "$ADMIN_PWD_INPUT")')
     ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
  echo "  Пароль веб-админки сохранён."
fi

# ── Администратор бота ────────────────────────────────────────────────────────
ADMIN_IDS_SET=$(sqlite3 /root/bot/vpn_bot.db "SELECT value FROM settings WHERE key='admin_ids' LIMIT 1;" 2>/dev/null || true)
if [ -z "$ADMIN_IDS_SET" ]; then
  echo ""
  echo "  Telegram ID администратора бота (узнать: @userinfobot)."
  read -rp "  ID, несколько через запятую (Enter — пропустить): " ADMIN_IDS_INPUT
  ADMIN_IDS_INPUT="${ADMIN_IDS_INPUT// /}"
  if [[ "$ADMIN_IDS_INPUT" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    sqlite3 /root/bot/vpn_bot.db \
      "INSERT INTO settings (key, value) VALUES ('admin_ids', '$ADMIN_IDS_INPUT')
       ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
    echo "  Администраторы бота: $ADMIN_IDS_INPUT"
  elif [ -n "$ADMIN_IDS_INPUT" ]; then
    echo "  Не похоже на ID (нужны цифры через запятую) — пропускаю, задайте в веб-админке."
  fi
fi

echo "\nНастраиваю автозапуск сервисов..."
cp service/vpn-bot.service /etc/systemd/system/
cp service/vpn-webadmin.service /etc/systemd/system/
cp service/xuiweb.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now vpn-bot.service vpn-webadmin.service xuiweb.service
systemctl enable --now xuiweb.service
echo "\nБот и веб-админка запущены и добавлены в автозагрузку!"

# ── Установка SUBPAGE ─────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Хотите установить SUBPAGE (страница подписки) на"
echo "  этом сервере, или он будет на внешнем сервере?"
echo ""
echo "  1) Установить SUBPAGE на этом сервере"
echo "  2) Пропустить — SUBPAGE на внешнем сервере"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -rp "Ваш выбор [1/2]: " subpage_choice

if [[ "$subpage_choice" == "1" ]]; then
  # SUBPAGE на этом же сервере — sub_page_url = домен бота
  SUBPAGE_DOMAIN="$DOMAIN"
  if [ -f "/root/bot/vpn_bot.db" ]; then
    sqlite3 /root/bot/vpn_bot.db \
      "INSERT INTO settings (key, value) VALUES ('sub_page_url', 'https://$SUBPAGE_DOMAIN')
       ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
    echo "sub_page_url → https://$SUBPAGE_DOMAIN"
  fi
  echo "\nКопирую SUBPAGE в /root/subpage..."
  cp -r /root/bot/subpage /root/subpage
  echo "Запускаю установку SUBPAGE..."
  cd /root/subpage
  bash install.sh
else
  # SUBPAGE на внешнем сервере — спрашиваем его домен
  echo ""
  echo "Укажите домен внешнего SUBPAGE (страницы подписки)."
  read -rp "Домен SUBPAGE [по умолчанию: $DOMAIN]: " SUBPAGE_DOMAIN_INPUT
  SUBPAGE_DOMAIN="${SUBPAGE_DOMAIN_INPUT:-$DOMAIN}"
  if [ -f "/root/bot/vpn_bot.db" ]; then
    sqlite3 /root/bot/vpn_bot.db \
      "INSERT INTO settings (key, value) VALUES ('sub_page_url', 'https://$SUBPAGE_DOMAIN')
       ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
    echo "sub_page_url → https://$SUBPAGE_DOMAIN"
  else
    echo "БД не найдена, пропускаю обновление sub_page_url."
  fi
  echo "\nПропускаем установку SUBPAGE."
fi

# ── Итоговый вывод ────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Установка завершена!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -n "$DOMAIN" ] && [ -n "$ADMIN_SECRET_PATH" ]; then
  echo ""
  echo "  🌐  Веб-админка:"
  echo "      https://$DOMAIN/$ADMIN_SECRET_PATH/"
  echo ""
  echo "  📡  Страница подписки (SUBPAGE):"
  echo "      https://$SUBPAGE_DOMAIN/sub/<uuid>"
fi
if [ -n "$ADMIN_PWD_GENERATED" ]; then
  echo ""
  echo "  🔑  Пароль веб-админки (сгенерирован, сохраните):"
  echo "      $ADMIN_PWD_GENERATED"
fi
echo ""
echo "  🔌  Remnawave 2.7.4: веб-админка → Remnawave → Base URL панели и API Token."
echo "  ℹ️   Токен бота и остальные настройки — в веб-админке."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"