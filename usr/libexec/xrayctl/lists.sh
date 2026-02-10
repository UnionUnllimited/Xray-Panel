#!/bin/sh

. /usr/libexec/xrayctl/common.sh

xr_lists_menu() {
  echo ""
  echo "Списки"
  echo "1) Обновить списки из URL"
  echo "2) Просмотр proxy.txt"
  echo "3) Просмотр direct.txt"
  echo "4) Просмотр block.txt"
  echo "0) Назад"
  printf 'Выберите пункт: '
  read -r pick
  case "$pick" in
    1) xr_update_lists ;;
    2) xr_show_list "$XRAYCTL_RULES_DIR/proxy.txt" ;;
    3) xr_show_list "$XRAYCTL_RULES_DIR/direct.txt" ;;
    4) xr_show_list "$XRAYCTL_RULES_DIR/block.txt" ;;
    0) return 0 ;;
    *) echo "Неверный выбор" ;;
  esac
}

xr_update_lists() {
  xr_ensure_paths
  if ! xr_require_cmd curl; then
    xr_log "curl не найден."
    return 1
  fi

  printf 'URL списка proxy.txt: '
  read -r proxy_url
  printf 'URL списка direct.txt: '
  read -r direct_url
  printf 'URL списка block.txt: '
  read -r block_url

  [ -n "$proxy_url" ] && curl -fsSL "$proxy_url" > "$XRAYCTL_RULES_DIR/proxy.txt"
  [ -n "$direct_url" ] && curl -fsSL "$direct_url" > "$XRAYCTL_RULES_DIR/direct.txt"
  [ -n "$block_url" ] && curl -fsSL "$block_url" > "$XRAYCTL_RULES_DIR/block.txt"

  xr_log "Списки обновлены."
}

xr_show_list() {
  local file="$1"
  if [ ! -f "$file" ]; then
    xr_log "Файл не найден: $file"
    return 1
  fi
  echo ""
  echo "--- $file ---"
  tail -n 200 "$file"
  echo ""
  read -r _
}
