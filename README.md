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
opkg install curl ca-bundle jq
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

Для обновления подписок и сборки конфига требуется `jq` (устанавливается автоматически в `install.sh`).

Если провайдер требует специальный заголовок, добавьте его в UCI и повторите обновление подписки:

```sh
uci set xrayctl.subscription.header='User-Agent: AtlantaWall'
uci commit xrayctl
```

## Полное удаление (для тестов)

```sh
curl -fsSL https://raw.githubusercontent.com/UnionUnllimited/Xray-Panel/codex/create-ssh-control-panel-for-xray/uninstall.sh | sh
```

## Формат outbounds.json

Файл должен содержать **JSON array** из outbound-объектов Xray. Каждый outbound должен иметь уникальный `tag`, а балансер использует список всех тегов.

Пример:

```json
[
  {
    "tag": "node_1",
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

Подписка загружается как base64, декодируется и фильтруется по строкам `vless://`. Далее панель строит `outbounds.json` и сразу пересобирает `config.json` с балансером по всем нодам.
