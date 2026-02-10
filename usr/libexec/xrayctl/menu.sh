#!/bin/sh

. /usr/libexec/xrayctl/common.sh
. /usr/libexec/xrayctl/subscription.sh
. /usr/libexec/xrayctl/lists.sh
. /usr/libexec/xrayctl/balancer.sh
. /usr/libexec/xrayctl/cron.sh
. /usr/libexec/xrayctl/xray_config.sh

xr_menu_header() {
  echo ""
  echo "XrayCTL (OpenWrt 24.10)"
  echo "======================="
}

xr_menu_footer() {
  echo ""
  echo "0) Выход"
  echo ""
  printf 'Выберите пункт: '
}

xr_menu_loop() {
  xr_ensure_paths
  while true; do
    xr_menu_header
    echo "1) Подписка / Ноды"
    echo "2) Балансер"
    echo "3) Списки"
    echo "4) Cron"
    echo "5) Редактор (nano)"
    echo "6) Собрать конфиг"
    echo "7) Перезапустить Xray"
    echo "8) Статус / Логи"
    xr_menu_footer
    read -r choice
    case "$choice" in
      1) xr_subscription_menu ;;
      2) xr_balancer_menu ;;
      3) xr_lists_menu ;;
      4) xr_cron_menu ;;
      5) xr_editor_menu ;;
      6) xr_build_config ;;
      7) xr_restart_xray ;;
      8) xr_status_logs ;;
      0) exit 0 ;;
      *) echo "Неверный выбор" ;;
    esac
  done
}

xr_editor_menu() {
  local editor
  editor="${EDITOR:-nano}"
  echo ""
  echo "Редактор: $editor"
  echo "1) /etc/xray/config.json"
  echo "2) /etc/config/xrayctl"
  echo "3) proxy.txt"
  echo "4) direct.txt"
  echo "5) block.txt"
  echo "0) Назад"
  printf 'Выберите файл: '
  read -r pick
  case "$pick" in
    1) $editor "$XRAY_CONFIG_FILE" ;;
    2) $editor "$XRAYCTL_UCI_CONFIG" ;;
    3) $editor "$XRAYCTL_RULES_DIR/proxy.txt" ;;
    4) $editor "$XRAYCTL_RULES_DIR/direct.txt" ;;
    5) $editor "$XRAYCTL_RULES_DIR/block.txt" ;;
    0) return 0 ;;
    *) echo "Неверный выбор" ;;
  esac
}

xr_restart_xray() {
  if xr_require_cmd /etc/init.d/xray; then
    /etc/init.d/xray restart
  else
    xr_log "init.d xray не найден. Перезапуск пропущен."
    xr_log "Установите пакет xray (например: opkg update && opkg install xray)."
  fi
}

xr_status_logs() {
  if xr_require_cmd /etc/init.d/xray; then
    /etc/init.d/xray status
  fi
  if [ -f /var/log/xray.log ]; then
    tail -n 50 /var/log/xray.log
  else
    xr_log "Логи /var/log/xray.log не найдены."
    xr_log "Проверьте, что Xray установлен и логирование включено."
  fi
  echo ""
  read -r _
}
