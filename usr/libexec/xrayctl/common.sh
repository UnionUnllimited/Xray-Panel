#!/bin/sh

XRAYCTL_ETC_DIR="/etc/xrayctl"
XRAYCTL_RULES_DIR="$XRAYCTL_ETC_DIR/rules"
XRAYCTL_OUTBOUNDS_FILE="$XRAYCTL_ETC_DIR/outbounds.json"
XRAY_CONFIG_FILE="/etc/xray/config.json"
XRAY_CONFIG_TMP="/tmp/xray-config.json"
XRAYCTL_UCI_CONFIG="/etc/config/xrayctl"

xr_log() {
  printf '%s\n' "$*"
}

xr_die() {
  xr_log "[xrayctl] $*"
  exit 1
}

xr_ensure_paths() {
  mkdir -p "$XRAYCTL_ETC_DIR" "$XRAYCTL_RULES_DIR" /etc/xray
  : > "$XRAYCTL_RULES_DIR/proxy.txt"
  : > "$XRAYCTL_RULES_DIR/direct.txt"
  : > "$XRAYCTL_RULES_DIR/block.txt"
  if [ ! -f "$XRAYCTL_OUTBOUNDS_FILE" ]; then
    printf '[]\n' > "$XRAYCTL_OUTBOUNDS_FILE"
  fi
}

xr_confirm() {
  printf '%s [y/N]: ' "$1"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

xr_require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

xr_get_uci() {
  local key="$1"
  if xr_require_cmd uci; then
    uci -q get "xrayctl.$key"
  fi
}

xr_write_atomic() {
  local tmp_file="$1"
  local target="$2"
  if [ ! -s "$tmp_file" ]; then
    xr_die "Пустой файл конфигурации: $tmp_file"
  fi
  mv "$tmp_file" "$target"
}

xr_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/\"/\\"/g'
}
