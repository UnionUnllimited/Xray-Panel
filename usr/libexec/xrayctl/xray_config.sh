#!/bin/sh

. /usr/libexec/xrayctl/common.sh

xr_build_config() {
  xr_ensure_paths

  if [ ! -f "$XRAYCTL_OUTBOUNDS_FILE" ]; then
    xr_die "Файл нод не найден: $XRAYCTL_OUTBOUNDS_FILE"
  fi

  local nodes_raw
  nodes_raw="$(cat "$XRAYCTL_OUTBOUNDS_FILE")"
  nodes_raw="$(printf '%s' "$nodes_raw" | tr -d '\r')"

  if [ -z "$nodes_raw" ] || [ "$nodes_raw" = "[]" ]; then
    xr_die "Ноды отсутствуют, Xray не стартует."
  fi

  local nodes_trimmed
  nodes_trimmed="$(printf '%s' "$nodes_raw" | sed '1s/^\[//; $s/\]$//')"
  if [ -z "$(printf '%s' "$nodes_trimmed" | tr -d ' \n\t')" ]; then
    xr_die "Ноды отсутствуют, Xray не стартует."
  fi

  local strategy
  local probe_url
  local probe_interval
  strategy="$(xr_get_uci balancer.strategy)"
  probe_url="$(xr_get_uci balancer.probe_url)"
  probe_interval="$(xr_get_uci balancer.probe_interval)"

  [ -z "$strategy" ] && strategy="leastPing"
  [ -z "$probe_url" ] && probe_url="https://www.gstatic.com/generate_204"
  [ -z "$probe_interval" ] && probe_interval="10s"

  cat > "$XRAY_CONFIG_TMP" <<EOF_CONF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "tproxy-in",
      "listen": "0.0.0.0",
      "port": 12345,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy"
        }
      }
    }
  ],
  "outbounds": [
EOF_CONF

  printf '%s\n' "$nodes_trimmed" >> "$XRAY_CONFIG_TMP"
  cat >> "$XRAY_CONFIG_TMP" <<EOF_CONF
,
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "observatory": {
    "subjectSelector": ["proxy"],
    "probeUrl": "$probe_url",
    "probeInterval": "$probe_interval"
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "balancers": [
      {
        "tag": "balancer",
        "selector": ["proxy"],
        "strategy": {
          "type": "$strategy"
        }
      }
    ],
    "rules": [
      {
        "type": "field",
        "outboundTag": "block",
        "domain": ["ext:$XRAYCTL_RULES_DIR/block.txt"],
        "ip": ["ext:$XRAYCTL_RULES_DIR/block.txt"]
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "domain": ["ext:$XRAYCTL_RULES_DIR/direct.txt"],
        "ip": ["ext:$XRAYCTL_RULES_DIR/direct.txt"]
      },
      {
        "type": "field",
        "balancerTag": "balancer",
        "domain": ["ext:$XRAYCTL_RULES_DIR/proxy.txt"],
        "ip": ["ext:$XRAYCTL_RULES_DIR/proxy.txt"]
      }
    ]
  }
}
EOF_CONF

  xr_write_atomic "$XRAY_CONFIG_TMP" "$XRAY_CONFIG_FILE"
  xr_log "Конфиг собран: $XRAY_CONFIG_FILE"
}
