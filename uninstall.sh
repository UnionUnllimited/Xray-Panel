#!/bin/sh
set -e

echo "[xrayctl] Удаление панели"

rm -f /usr/bin/xrayctl
rm -rf /usr/libexec/xrayctl

rm -rf /etc/xrayctl
rm -f /etc/config/xrayctl

echo "[xrayctl] Удалены файлы панели."
echo "[xrayctl] Конфиг Xray (/etc/xray/config.json) не тронут."
