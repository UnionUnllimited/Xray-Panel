#!/bin/sh

. /usr/libexec/xrayctl/common.sh

xr_balancer_menu() {
  echo ""
  echo "Балансер"
  echo "1) Показать настройки"
  echo "2) Установить стратегию"
  echo "3) Установить probe_url"
  echo "4) Установить probe_interval"
  echo "0) Назад"
  printf 'Выберите пункт: '
  read -r pick
  case "$pick" in
    1) xr_show_balancer ;;
    2) xr_set_strategy ;;
    3) xr_set_probe_url ;;
    4) xr_set_probe_interval ;;
    0) return 0 ;;
    *) echo "Неверный выбор" ;;
  esac
}

xr_show_balancer() {
  echo ""
  echo "strategy: $(xr_get_uci balancer.strategy)"
  echo "probe_url: $(xr_get_uci balancer.probe_url)"
  echo "probe_interval: $(xr_get_uci balancer.probe_interval)"
  echo ""
  read -r _
}

xr_set_strategy() {
  echo "Стратегия (leastPing | random | roundRobin):"
  read -r strategy
  if xr_require_cmd uci; then
    uci set xrayctl.balancer.strategy="$strategy"
    uci commit xrayctl
    xr_log "Стратегия сохранена."
  else
    xr_log "uci не найден."
  fi
}

xr_set_probe_url() {
  echo "probe_url (например https://www.gstatic.com/generate_204):"
  read -r probe_url
  if xr_require_cmd uci; then
    uci set xrayctl.balancer.probe_url="$probe_url"
    uci commit xrayctl
    xr_log "probe_url сохранён."
  else
    xr_log "uci не найден."
  fi
}

xr_set_probe_interval() {
  echo "probe_interval (например 10s):"
  read -r probe_interval
  if xr_require_cmd uci; then
    uci set xrayctl.balancer.probe_interval="$probe_interval"
    uci commit xrayctl
    xr_log "probe_interval сохранён."
  else
    xr_log "uci не найден."
  fi
}
