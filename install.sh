#!/bin/sh
set -e

REPO_URL="${REPO_URL:-https://github.com/your-org/Xray-Panel}"
REF="${REF:-main}"
DEST_DIR="${DEST_DIR:-/tmp/xrayctl-install}"

echo "[xrayctl] Загрузка установщика из $REPO_URL ($REF)"

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$REPO_URL/archive/refs/heads/$REF.tar.gz" -o "$DEST_DIR/src.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$DEST_DIR/src.tar.gz" "$REPO_URL/archive/refs/heads/$REF.tar.gz"
else
  echo "[xrayctl] Требуется curl или wget."
  exit 1
fi

tar -xzf "$DEST_DIR/src.tar.gz" -C "$DEST_DIR"

SRC_DIR="$(find "$DEST_DIR" -maxdepth 1 -type d -name 'Xray-Panel-*' | head -n1)"
if [ -z "$SRC_DIR" ]; then
  echo "[xrayctl] Не удалось найти исходники."
  exit 1
fi

echo "[xrayctl] Копирование файлов в /usr и /etc"
cp -r "$SRC_DIR/usr/"* /usr/
cp -r "$SRC_DIR/etc/"* /etc/

chmod +x /usr/bin/xrayctl /usr/libexec/xrayctl/*.sh

echo "[xrayctl] Установка завершена."
echo "[xrayctl] Запуск панели: xrayctl"
