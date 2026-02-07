# XrayCTL (консольная панель для OpenWrt 24.10)

Минимальная консольная панель управления Xray, ориентированная на PassWall-подобный UX, но без LuCI/geoip/geosite и без китайской логики.

## Основные принципы

- Только списки маршрутизации (proxy/direct/block).
- Никаких geosite/geoip.
- Управление через SSH (TUI/CLI).
- Поддержка подписок через локальный subconverter.

## Структура

- `usr/bin/xrayctl` — вход в панель.
- `usr/libexec/xrayctl/*` — модульные скрипты.
- `/etc/xrayctl/rules/*.txt` — списки.
- `/etc/xrayctl/outbounds.json` — список нод (JSON array).
- `/etc/xray/config.json` — итоговый конфиг Xray.

## Быстрый старт

```sh
xrayctl
```

## Установка шаг за шагом (OpenWrt)

1) Подключитесь по SSH.
2) Установите зависимости:

```sh
opkg update
opkg install curl ca-bundle
```

3) Запустите установку:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/UnionUnllimited/Xray-Panel/codex/create-ssh-control-panel-for-xray/install.sh)"
```

4) Откройте панель:

```sh
xrayctl
```

## Установка одной командой

На OpenWrt (через SSH):

```sh
curl -fsSL https://raw.githubusercontent.com/UnionUnllimited/Xray-Panel/codex/create-ssh-control-panel-for-xray/install.sh | sh
```

Если видите ошибки вида `diff: not found` или `+++ not found`, значит скачивается не raw-скрипт. Проверьте, что ссылка начинается с `https://raw.githubusercontent.com/` и ведёт на файл `install.sh`, а не на страницу `github.com/.../blob/...`.

Если репозиторий в другом месте — укажите `REPO_URL` и ветку `REF`:

```sh
REPO_URL="https://github.com/UnionUnllimited/Xray-Panel" REF="codex/create-ssh-control-panel-for-xray" sh -c "$(curl -fsSL https://raw.githubusercontent.com/UnionUnllimited/Xray-Panel/codex/create-ssh-control-panel-for-xray/install.sh)"
```

Если подписка не парсится, проверьте ответ напрямую:

```sh
curl -vL --connect-timeout 10 --max-time 30 "https://your-subscription.example/your-token"
```

Для JSON с `outbounds` требуется `jsonfilter` (устанавливается автоматически в `install.sh`).

## Полное удаление (для тестов)

```sh
curl -fsSL https://raw.githubusercontent.com/UnionUnllimited/Xray-Panel/codex/create-ssh-control-panel-for-xray/uninstall.sh | sh
```

## Формат outbounds.json

Файл должен содержать **JSON array** из outbound-объектов Xray. Каждый outbound должен иметь тег `proxy`, чтобы работал балансер.

Пример:

```json
[
  {
    "tag": "proxy",
    "protocol": "vless",
    "settings": {
      "vnext": [
        {
          "address": "example.com",
          "port": 443,
          "users": [
            {
              "id": "UUID",
              "encryption": "none"
            }
          ]
        }
      ]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "tls"
    }
  }
]
```

## Списки

- `proxy.txt` — только прокси
- `direct.txt` — напрямую
- `block.txt` — блокировка

## Cron

Cron управляется через меню, записи помечены `# xrayctl`.

## Подписки

Панель ожидает локальный subconverter, доступный по `http://127.0.0.1:25500/sub` (можно изменить в `/etc/config/xrayctl`).
Если подписка содержит `proxies:` или `proxy-groups:`, она будет отправлена в subconverter (target=v2ray) и преобразована в ссылки `vless://`, `vmess://`, `trojan://`.
Далее панель конвертирует эти ссылки в `outbounds.json`. Для `vmess://` требуется `jsonfilter`.

## Примечание

Проект — скелет/основа. Для работы подписок требуется локальный subconverter, который должен отдавать список `vless://` и/или готовый JSON outbounds.
