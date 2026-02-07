#!/bin/sh

. /usr/libexec/xrayctl/common.sh

xr_subscription_menu() {
  echo ""
  echo "Подписка / Ноды"
  echo "1) Обновить подписку"
  echo "2) Показать текущие ноды"
  echo "3) Очистить ноды"
  echo "0) Назад"
  printf 'Выберите пункт: '
  read -r pick
  case "$pick" in
    1) xr_update_subscription ;;
    2) xr_show_nodes ;;
    3) xr_clear_nodes ;;
    0) return 0 ;;
    *) echo "Неверный выбор" ;;
  esac
}

xr_choose_user_agent() {
  echo "Выберите User-Agent:"
  echo "1) clash"
  echo "2) ClashForWindows"
  echo "3) sing-box"
  echo "4) mihomo"
  echo "5) v2rayN"
  echo "6) browser"
  echo "7) AtlantaWall"
  printf 'Выбор: '
  read -r ua_pick
  case "$ua_pick" in
    1) echo "clash" ;;
    2) echo "ClashForWindows" ;;
    3) echo "sing-box" ;;
    4) echo "mihomo" ;;
    5) echo "v2rayN" ;;
    6) echo "Mozilla/5.0" ;;
    7) echo "AtlantaWall" ;;
    *) echo "clash" ;;
  esac
}

xr_update_subscription() {
  xr_ensure_paths
  printf 'URL подписки: '
  read -r sub_url
  if [ -z "$sub_url" ]; then
    xr_log "Пустой URL."
    return 1
  fi

  local ua
  ua="$(xr_get_uci subscription.user_agent)"
  if [ -z "$ua" ]; then
    case "$sub_url" in
      *atlanta-subs.ru*) ua="AtlantaWall" ;;
      *) ua="$(xr_choose_user_agent)" ;;
    esac
  fi
  XRAYCTL_USER_AGENT="$ua"

  if ! xr_require_cmd curl; then
    xr_log "curl не найден, обновление невозможно."
    return 1
  fi

  local sub_data
  xr_log "Загрузка подписки..."
  sub_data="$(curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 2 \
    -H "User-Agent: $ua" "$sub_url")"
  if [ -z "$sub_data" ]; then
    xr_log "Не удалось загрузить подписку."
    xr_log "Проверьте доступность URL, DNS и подключение к интернету."
    return 1
  fi

  xr_log "Подписка загружена."
  xr_log "Сохранение данных в $XRAYCTL_ETC_DIR/subscription.raw"
  printf '%s\n' "$sub_data" > "$XRAYCTL_ETC_DIR/subscription.raw"

  if xr_convert_subscription "$sub_url" "$sub_data"; then
    xr_log "Подписка преобразована в outbounds."
  else
    xr_log "Не удалось преобразовать подписку."
  fi

  if [ -f "$XRAYCTL_OUTBOUNDS_FILE" ]; then
    local node_count
    node_count="$(grep -c '"protocol"' "$XRAYCTL_OUTBOUNDS_FILE" 2>/dev/null || true)"
    xr_log "Нод в outbounds: ${node_count:-0}"
    if [ "${node_count:-0}" -eq 0 ]; then
      xr_log "Ноды не найдены. Проверьте $XRAYCTL_ETC_DIR/subscription.raw"
      xr_log "Поддерживаются vless/vmess/trojan; для vmess нужен пакет jsonfilter."
    fi
  fi
}

xr_show_nodes() {
  if [ ! -f "$XRAYCTL_OUTBOUNDS_FILE" ]; then
    xr_log "Файл нод не найден."
    return 1
  fi
  echo ""
  echo "Текущие ноды (JSON):"
  cat "$XRAYCTL_OUTBOUNDS_FILE"
  echo ""
  read -r _
}

xr_clear_nodes() {
  if xr_confirm "Очистить список нод?"; then
    printf '[]\n' > "$XRAYCTL_OUTBOUNDS_FILE"
    xr_log "Ноды очищены."
  fi
}

xr_normalize_subscription_payload() {
  local payload="$1"
  if [ -z "$payload" ]; then
    return 0
  fi

  local trimmed
  trimmed="$(xr_trim_payload "$payload")"
  if xr_is_http_url "$trimmed"; then
    local fetched
    fetched="$(xr_fetch_url "$trimmed")"
    if [ -n "$fetched" ]; then
      payload="$fetched"
    fi
  fi

  if xr_contains_links "$payload" || xr_contains_clash "$payload" || xr_contains_json_outbounds "$payload"; then
    printf '%s' "$payload"
    return 0
  fi

  if xr_require_cmd base64; then
    local decoded
    decoded="$(xr_base64_decode "$payload")"
    if xr_contains_links "$decoded" || xr_contains_clash "$decoded" || xr_contains_json_outbounds "$decoded"; then
      printf '%s' "$decoded"
      return 0
    fi
  fi

  printf '%s' "$payload"
}

xr_trim_payload() {
  printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

xr_is_http_url() {
  case "$1" in
    http://*|https://*) return 0 ;;
    *) return 1 ;;
  esac
}

xr_fetch_url() {
  local url="$1"
  local ua
  ua="${XRAYCTL_USER_AGENT:-xrayctl}"
  if ! xr_require_cmd curl; then
    return 0
  fi
  curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 2 \
    -H "User-Agent: $ua" "$url"
}

xr_contains_links() {
  printf '%s' "$1" | grep -q 'vless://' \
    || printf '%s' "$1" | grep -q 'vmess://' \
    || printf '%s' "$1" | grep -q 'trojan://'
}

xr_contains_clash() {
  printf '%s' "$1" | grep -q 'proxies:' \
    || printf '%s' "$1" | grep -q 'proxy-groups:'
}

xr_contains_json_outbounds() {
  printf '%s' "$1" | grep -q '"protocol"' \
    && (printf '%s' "$1" | grep -q '"outbounds"' || printf '%s' "$1" | grep -q '^\s*\[')
}

xr_convert_subscription() {
  local sub_url="$1"
  local sub_data="$2"
  local subconverter_url
  subconverter_url="$(xr_get_uci subscription.subconverter_url)"
  [ -z "$subconverter_url" ] && subconverter_url="http://127.0.0.1:25500/sub"

  local normalized
  normalized="$(xr_normalize_subscription_payload "$sub_data")"

  local links_data
  links_data=""

  if xr_contains_clash "$normalized"; then
    xr_log "Обнаружен Clash/YAML. Используем subconverter."
    links_data="$(curl -fsSL --connect-timeout 5 --max-time 30 --retry 2 --retry-delay 2 \
      -H "User-Agent: xrayctl" \
      "${subconverter_url}?target=v2ray&url=${sub_url}&list=true")"
    if [ -z "$links_data" ]; then
      xr_log "subconverter не вернул данные."
      return 1
    fi
    normalized="$(xr_normalize_subscription_payload "$links_data")"
    if xr_contains_links "$normalized"; then
      links_data="$normalized"
      xr_log "Подписка преобразована через subconverter."
      printf '%s\n' "$links_data" > "$XRAYCTL_ETC_DIR/subscription.decoded"
    else
      links_data="$links_data"
    fi
  else
    links_data="$normalized"
  fi

  if xr_contains_links "$links_data"; then
    if [ -n "$normalized" ] && [ "$normalized" != "$sub_data" ]; then
      xr_log "Подписка декодирована из base64."
      printf '%s\n' "$links_data" > "$XRAYCTL_ETC_DIR/subscription.decoded"
    fi
  fi

  if xr_contains_json_outbounds "$links_data"; then
    xr_log "Обнаружен JSON с outbounds."
    if xr_write_outbounds_from_json "$links_data"; then
      return 0
    fi
  fi

  if ! xr_contains_links "$links_data"; then
    xr_log "В подписке нет vless/vmess/trojan ссылок."
    return 1
  fi

  xr_links_to_outbounds "$links_data"
}

xr_write_outbounds_from_json() {
  local data="$1"
  local tmp_file
  tmp_file="$(mktemp)"

  if printf '%s' "$data" | grep -q '^\s*\[' && xr_require_cmd jsonfilter; then
    if xr_outbounds_from_config_list "$data" "$tmp_file"; then
      xr_write_atomic "$tmp_file" "$XRAYCTL_OUTBOUNDS_FILE"
      return 0
    fi
  fi

  if printf '%s' "$data" | grep -q '"outbounds"' && xr_require_cmd jsonfilter; then
    jsonfilter -e '@.outbounds' <<EOF_JSON > "$tmp_file"
$data
EOF_JSON
    if [ -s "$tmp_file" ]; then
      xr_write_atomic "$tmp_file" "$XRAYCTL_OUTBOUNDS_FILE"
      return 0
    fi
  fi

  if printf '%s' "$data" | grep -q '"outbounds"' && ! xr_require_cmd jsonfilter; then
    xr_log "Для JSON с outbounds нужен пакет jsonfilter."
  fi

  if printf '%s' "$data" | grep -q '^\s*\['; then
    printf '%s\n' "$data" > "$tmp_file"
    xr_write_atomic "$tmp_file" "$XRAYCTL_OUTBOUNDS_FILE"
    return 0
  fi

  rm -f "$tmp_file"
  return 1
}

xr_outbounds_from_config_list() {
  local data="$1"
  local output_file="$2"
  local found="0"

  printf '[\n' > "$output_file"
  local first="yes"
  local i=0
  while [ "$i" -lt 50 ]; do
    local remarks
    remarks="$(jsonfilter -e "@[$i].remarks" <<EOF_JSON
$data
EOF_JSON
)"
    if [ -z "$remarks" ]; then
      i=$((i + 1))
      continue
    fi

    local j=0
    while [ "$j" -lt 20 ]; do
      local tag protocol
      tag="$(jsonfilter -e "@[$i].outbounds[$j].tag" <<EOF_JSON
$data
EOF_JSON
)"
      protocol="$(jsonfilter -e "@[$i].outbounds[$j].protocol" <<EOF_JSON
$data
EOF_JSON
)"
      if [ "$tag" = "proxy" ] && [ "$protocol" = "vless" ]; then
        local address port uuid flow network security sni public_key fingerprint
        address="$(jsonfilter -e "@[$i].outbounds[$j].settings.vnext[0].address" <<EOF_JSON
$data
EOF_JSON
)"
        port="$(jsonfilter -e "@[$i].outbounds[$j].settings.vnext[0].port" <<EOF_JSON
$data
EOF_JSON
)"
        uuid="$(jsonfilter -e "@[$i].outbounds[$j].settings.vnext[0].users[0].id" <<EOF_JSON
$data
EOF_JSON
)"
        flow="$(jsonfilter -e "@[$i].outbounds[$j].settings.vnext[0].users[0].flow" <<EOF_JSON
$data
EOF_JSON
)"
        network="$(jsonfilter -e "@[$i].outbounds[$j].streamSettings.network" <<EOF_JSON
$data
EOF_JSON
)"
        security="$(jsonfilter -e "@[$i].outbounds[$j].streamSettings.security" <<EOF_JSON
$data
EOF_JSON
)"
        sni="$(jsonfilter -e "@[$i].outbounds[$j].streamSettings.realitySettings.serverName" <<EOF_JSON
$data
EOF_JSON
)"
        public_key="$(jsonfilter -e "@[$i].outbounds[$j].streamSettings.realitySettings.publicKey" <<EOF_JSON
$data
EOF_JSON
)"
        fingerprint="$(jsonfilter -e "@[$i].outbounds[$j].streamSettings.realitySettings.fingerprint" <<EOF_JSON
$data
EOF_JSON
)"

        if [ -n "$address" ] && [ -n "$port" ] && [ -n "$uuid" ]; then
          if [ "$first" = "yes" ]; then
            first="no"
          else
            printf ',\n' >> "$output_file"
          fi
          found="1"
          cat <<EOF_OUT >> "$output_file"
  {
    "tag": "$(xr_json_escape "$remarks")",
    "protocol": "vless",
    "settings": {
      "vnext": [
        {
          "address": "$(xr_json_escape "$address")",
          "port": $port,
          "users": [
            {
              "id": "$(xr_json_escape "$uuid")",
              "encryption": "none",
              "flow": "$(xr_json_escape "$flow")"
            }
          ]
        }
      ]
    },
    "streamSettings": {
      "network": "$(xr_json_escape "${network:-tcp}")",
      "security": "$(xr_json_escape "${security:-none}")",
      "realitySettings": {
        "serverName": "$(xr_json_escape "$sni")",
        "publicKey": "$(xr_json_escape "$public_key")",
        "fingerprint": "$(xr_json_escape "$fingerprint")"
      }
    }
  }
EOF_OUT
        fi
      fi
      j=$((j + 1))
    done
    i=$((i + 1))
  done

  printf '\n]\n' >> "$output_file"
  if [ "$found" = "1" ]; then
    return 0
  fi
  return 1
}

xr_base64_decode() {
  local data
  data="$(printf '%s' "$1" | tr -d '\n\r')"
  if [ -z "$data" ]; then
    return 0
  fi

  local normalized
  normalized="$(printf '%s' "$data" | tr '_-' '/+')"
  case "$normalized" in
    *==|*=) ;;
    *[!A-Za-z0-9+/=]*)
      printf '%s' "$data"
      return 0
      ;;
    *)
      case $((${#normalized} % 4)) in
        2) normalized="${normalized}==" ;;
        3) normalized="${normalized}=" ;;
      esac
      ;;
  esac

  printf '%s' "$normalized" | base64 -d 2>/dev/null
}

xr_links_to_outbounds() {
  local links_data="$1"
  local tmp_file
  tmp_file="$(mktemp)"
  printf '[\n' > "$tmp_file"

  local first="yes"
  printf '%s\n' "$links_data" | tr '\r' '\n' | while IFS= read -r line; do
    case "$line" in
      vless://*)
        local outbound
        outbound="$(xr_vless_to_outbound "$line")"
        if [ -n "$outbound" ]; then
          if [ "$first" = "yes" ]; then
            first="no"
          else
            printf ',\n' >> "$tmp_file"
          fi
          printf '%s' "$outbound" >> "$tmp_file"
        fi
        ;;
      vmess://*)
        local outbound_vmess
        outbound_vmess="$(xr_vmess_to_outbound "$line")"
        if [ -n "$outbound_vmess" ]; then
          if [ "$first" = "yes" ]; then
            first="no"
          else
            printf ',\n' >> "$tmp_file"
          fi
          printf '%s' "$outbound_vmess" >> "$tmp_file"
        fi
        ;;
      trojan://*)
        local outbound_trojan
        outbound_trojan="$(xr_trojan_to_outbound "$line")"
        if [ -n "$outbound_trojan" ]; then
          if [ "$first" = "yes" ]; then
            first="no"
          else
            printf ',\n' >> "$tmp_file"
          fi
          printf '%s' "$outbound_trojan" >> "$tmp_file"
        fi
        ;;
      *) ;;
    esac
  done

  printf '\n]\n' >> "$tmp_file"
  xr_write_atomic "$tmp_file" "$XRAYCTL_OUTBOUNDS_FILE"
}

xr_vless_to_outbound() {
  local link="$1"
  link="${link#vless://}"

  local name=""
  case "$link" in
    *#*)
      name="${link#*#}"
      link="${link%%#*}"
      ;;
  esac

  local params=""
  case "$link" in
    *\?*)
      params="${link#*\?}"
      link="${link%%\?*}"
      ;;
  esac

  local user_host="$link"
  local uuid="${user_host%%@*}"
  local hostport="${user_host#*@}"
  local host="${hostport%%:*}"
  local port="${hostport##*:}"

  if [ -z "$uuid" ] || [ -z "$host" ] || [ -z "$port" ]; then
    xr_log "Пропуск некорректной ссылки vless://"
    return 0
  fi

  local security=""
  local transport="tcp"
  local sni=""
  local flow=""
  local ws_path=""
  local ws_host=""
  local grpc_service=""

  IFS='&'
  for kv in $params; do
    local key="${kv%%=*}"
    local value="${kv#*=}"
    case "$key" in
      security) security="$value" ;;
      type) transport="$value" ;;
      sni) sni="$value" ;;
      flow) flow="$value" ;;
      path) ws_path="$value" ;;
      host) ws_host="$value" ;;
      serviceName) grpc_service="$value" ;;
    esac
  done
  unset IFS

  [ -z "$security" ] && security="none"
  [ -z "$transport" ] && transport="tcp"

  local tag
  tag="proxy"
  if [ -n "$name" ]; then
    tag="proxy-$(xr_json_escape "$name")"
  fi

  local stream_settings
  stream_settings="\"network\": \"${transport}\", \"security\": \"${security}\""
  if [ -n "$sni" ]; then
    stream_settings="${stream_settings}, \"tlsSettings\": {\"serverName\": \"$(xr_json_escape "$sni")\"}"
  fi

  if [ "$transport" = "ws" ]; then
    stream_settings="${stream_settings}, \"wsSettings\": {\"path\": \"$(xr_json_escape "$ws_path")\""
    if [ -n "$ws_host" ]; then
      stream_settings="${stream_settings}, \"headers\": {\"Host\": \"$(xr_json_escape "$ws_host")\"}"
    fi
    stream_settings="${stream_settings}}"
  fi

  if [ "$transport" = "grpc" ]; then
    stream_settings="${stream_settings}, \"grpcSettings\": {\"serviceName\": \"$(xr_json_escape "$grpc_service")\"}"
  fi

  cat <<EOF_OUT
  {
    "tag": "$tag",
    "protocol": "vless",
    "settings": {
      "vnext": [
        {
          "address": "$(xr_json_escape "$host")",
          "port": $port,
          "users": [
            {
              "id": "$(xr_json_escape "$uuid")",
              "encryption": "none",
              "flow": "$(xr_json_escape "$flow")"
            }
          ]
        }
      ]
    },
    "streamSettings": {
      $stream_settings
    }
  }
EOF_OUT
}

xr_vmess_to_outbound() {
  local link="$1"
  local payload
  payload="${link#vmess://}"

  if ! xr_require_cmd base64; then
    xr_log "base64 не найден, vmess пропущен."
    return 0
  fi

  local decoded
  decoded="$(printf '%s' "$payload" | tr -d '\n\r' | base64 -d 2>/dev/null)"
  if [ -z "$decoded" ]; then
    xr_log "Не удалось декодировать vmess."
    return 0
  fi

  if ! xr_require_cmd jsonfilter; then
    xr_log "jsonfilter не найден, vmess пропущен."
    return 0
  fi

  local host port uuid aid net tls sni host_header path scy type
  host="$(printf '%s' "$decoded" | jsonfilter -e '@.add')"
  port="$(printf '%s' "$decoded" | jsonfilter -e '@.port')"
  uuid="$(printf '%s' "$decoded" | jsonfilter -e '@.id')"
  aid="$(printf '%s' "$decoded" | jsonfilter -e '@.aid')"
  net="$(printf '%s' "$decoded" | jsonfilter -e '@.net')"
  tls="$(printf '%s' "$decoded" | jsonfilter -e '@.tls')"
  sni="$(printf '%s' "$decoded" | jsonfilter -e '@.sni')"
  host_header="$(printf '%s' "$decoded" | jsonfilter -e '@.host')"
  path="$(printf '%s' "$decoded" | jsonfilter -e '@.path')"
  scy="$(printf '%s' "$decoded" | jsonfilter -e '@.scy')"
  type="$(printf '%s' "$decoded" | jsonfilter -e '@.type')"

  if [ -z "$host" ] || [ -z "$port" ] || [ -z "$uuid" ]; then
    xr_log "Некорректный vmess."
    return 0
  fi

  [ -z "$net" ] && net="tcp"
  [ -z "$scy" ] && scy="auto"

  local security="none"
  if [ "$tls" = "tls" ]; then
    security="tls"
  fi

  local stream_settings
  stream_settings="\"network\": \"${net}\", \"security\": \"${security}\""
  if [ -n "$sni" ]; then
    stream_settings="${stream_settings}, \"tlsSettings\": {\"serverName\": \"$(xr_json_escape "$sni")\"}"
  fi

  if [ "$net" = "ws" ]; then
    stream_settings="${stream_settings}, \"wsSettings\": {\"path\": \"$(xr_json_escape "$path")\""
    if [ -n "$host_header" ]; then
      stream_settings="${stream_settings}, \"headers\": {\"Host\": \"$(xr_json_escape "$host_header")\"}"
    fi
    stream_settings="${stream_settings}}"
  fi

  cat <<EOF_OUT
  {
    "tag": "proxy",
    "protocol": "vmess",
    "settings": {
      "vnext": [
        {
          "address": "$(xr_json_escape "$host")",
          "port": $port,
          "users": [
            {
              "id": "$(xr_json_escape "$uuid")",
              "alterId": ${aid:-0},
              "security": "$(xr_json_escape "$scy")"
            }
          ]
        }
      ]
    },
    "streamSettings": {
      $stream_settings
    }
  }
EOF_OUT
}

xr_trojan_to_outbound() {
  local link="$1"
  link="${link#trojan://}"

  local name=""
  case "$link" in
    *#*)
      name="${link#*#}"
      link="${link%%#*}"
      ;;
  esac

  local params=""
  case "$link" in
    *\?*)
      params="${link#*\?}"
      link="${link%%\?*}"
      ;;
  esac

  local pass_host="$link"
  local password="${pass_host%%@*}"
  local hostport="${pass_host#*@}"
  local host="${hostport%%:*}"
  local port="${hostport##*:}"

  if [ -z "$password" ] || [ -z "$host" ] || [ -z "$port" ]; then
    xr_log "Пропуск некорректной ссылки trojan://"
    return 0
  fi

  local transport="tcp"
  local sni=""
  local ws_path=""
  local ws_host=""

  IFS='&'
  for kv in $params; do
    local key="${kv%%=*}"
    local value="${kv#*=}"
    case "$key" in
      type) transport="$value" ;;
      sni) sni="$value" ;;
      path) ws_path="$value" ;;
      host) ws_host="$value" ;;
    esac
  done
  unset IFS

  local tag="proxy"
  if [ -n "$name" ]; then
    tag="proxy-$(xr_json_escape "$name")"
  fi

  local stream_settings
  stream_settings="\"network\": \"${transport}\", \"security\": \"tls\""
  if [ -n "$sni" ]; then
    stream_settings="${stream_settings}, \"tlsSettings\": {\"serverName\": \"$(xr_json_escape "$sni")\"}"
  fi

  if [ "$transport" = "ws" ]; then
    stream_settings="${stream_settings}, \"wsSettings\": {\"path\": \"$(xr_json_escape "$ws_path")\""
    if [ -n "$ws_host" ]; then
      stream_settings="${stream_settings}, \"headers\": {\"Host\": \"$(xr_json_escape "$ws_host")\"}"
    fi
    stream_settings="${stream_settings}}"
  fi

  cat <<EOF_OUT
  {
    "tag": "$tag",
    "protocol": "trojan",
    "settings": {
      "servers": [
        {
          "address": "$(xr_json_escape "$host")",
          "port": $port,
          "password": "$(xr_json_escape "$password")"
        }
      ]
    },
    "streamSettings": {
      $stream_settings
    }
  }
EOF_OUT
}
