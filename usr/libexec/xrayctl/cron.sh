#!/bin/sh

. /usr/libexec/xrayctl/common.sh

XRAYCTL_CRON_MARK="# xrayctl"

xr_cron_menu() {
  echo ""
  echo "Cron"
  echo "1) Показать crontab"
  echo "2) Включить задачи"
  echo "3) Отключить задачи"
  echo "4) Редактировать расписание"
  echo "0) Назад"
  printf 'Выберите пункт: '
  read -r pick
  case "$pick" in
    1) xr_show_cron ;;
    2) xr_enable_cron ;;
    3) xr_disable_cron ;;
    4) xr_edit_cron ;;
    0) return 0 ;;
    *) echo "Неверный выбор" ;;
  esac
}

xr_show_cron() {
  if xr_require_cmd crontab; then
    crontab -l 2>/dev/null | sed -n '/xrayctl/p'
  else
    xr_log "crontab не найден."
  fi
  echo ""
  read -r _
}

xr_enable_cron() {
  xr_edit_cron
}

xr_disable_cron() {
  if ! xr_require_cmd crontab; then
    xr_log "crontab не найден."
    return 1
  fi
  crontab -l 2>/dev/null | sed '/xrayctl/d' | crontab -
  xr_log "Задачи удалены."
}

xr_edit_cron() {
  if ! xr_require_cmd crontab; then
    xr_log "crontab не найден."
    return 1
  fi

  echo "Введите расписание обновления подписки (cron format):"
  read -r sub_schedule
  echo "Введите расписание обновления списков (cron format):"
  read -r list_schedule
  echo "Введите расписание rebuild+restart (cron format):"
  read -r rebuild_schedule

  {
    crontab -l 2>/dev/null | sed '/xrayctl/d'
    [ -n "$sub_schedule" ] && echo "$sub_schedule /usr/bin/xrayctl sub-update $XRAYCTL_CRON_MARK"
    [ -n "$list_schedule" ] && echo "$list_schedule /usr/bin/xrayctl list-update $XRAYCTL_CRON_MARK"
    [ -n "$rebuild_schedule" ] && echo "$rebuild_schedule /usr/bin/xrayctl rebuild $XRAYCTL_CRON_MARK"
  } | crontab -

  xr_log "Cron обновлён."
}
