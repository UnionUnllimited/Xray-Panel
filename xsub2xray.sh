#!/bin/sh
set -eu

SUB_URL="${1:-}"
OUT_CFG="${2:-/etc/xray/config.json}"

[ -n "$SUB_URL" ] || { echo "Usage: $0 <sub_url> [output_config]"; exit 2; }

TMP_RAW="/tmp/xsub.raw"
TMP_TXT="/tmp/xsub.txt"
TMP_JSON="/tmp/xsub.outbounds.json"

curl -fsSL "$SUB_URL" -o "$TMP_RAW"

base64 -d "$TMP_RAW" 2>/dev/null | tr -d '\r' | grep -E '^vless://' > "$TMP_TXT" || true
[ -s "$TMP_TXT" ] || { echo "No vless:// entries after decode"; exit 3; }

urldecode() { printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%/\\x/g')"; }

echo '[]' > "$TMP_JSON"

i=0

while IFS= read -r line; do
  i=$((i+1))

  uri="${line#vless://}"

  name=""
  case "$uri" in
    *"#"*)
      name="${uri#*#}"
      uri="${uri%%#*}"
      name="$(urldecode "$name")"
      ;;
  esac

  query=""
  case "$uri" in
    *"?"*)
      query="${uri#*\?}"
      uri="${uri%%\?*}"
      ;;
  esac

  uuid="${uri%@*}"
  hp="${uri#*@}"

  host="${hp%:*}"
  port="${hp##*:}"

  security=""
  net="tcp"
  flow=""
  sni=""
  fp="random"
  pbk=""
  sid=""

  oldIFS="$IFS"
  IFS="&"
  for kv in $query; do
    k="${kv%%=*}"
    v="${kv#*=}"
    v="$(urldecode "$v")"
    case "$k" in
      security) security="$v" ;;
      type) net="$v" ;;
      flow) flow="$v" ;;
      sni) sni="$v" ;;
      fp) fp="$v" ;;
      pbk) pbk="$v" ;;
      sid) sid="$v" ;;
    esac
  done
  IFS="$oldIFS"

  tag="node_$i"
  remark="$name"
  [ -n "$remark" ] || remark="$tag"

  node_json="$(jq -n \
    --arg tag "$tag" \
    --arg remark "$remark" \
    --arg host "$host" \
    --argjson port "$port" \
    --arg uuid "$uuid" \
    --arg flow "$flow" \
    --arg security "$security" \
    --arg net "$net" \
    --arg sni "$sni" \
    --arg fp "$fp" \
    --arg pbk "$pbk" \
    --arg sid "$sid" \
    '
    def add_flow:
      if ($flow|length) > 0 then . + {flow:$flow} else . end;

    def mk_reality:
      {
        show:false,
        fingerprint:(if ($fp|length)>0 then $fp else "random" end),
        serverName:$sni,
        publicKey:$pbk,
        shortId:$sid
      };

    {
      tag: $tag,
      protocol: "vless",
      settings: {
        vnext: [{
          address: $host,
          port: $port,
          users: [ ( {id:$uuid, encryption:"none"} | add_flow ) ]
        }]
      },
      streamSettings:
        (
          if ($net|length)>0 then
            {
              network:$net,
              security:(if ($security|length)>0 then $security else "none" end)
            }
          else
            { network:"tcp", security:(if ($security|length)>0 then $security else "none" end) }
          end
          | if $security=="reality" then . + {realitySettings: mk_reality} else . end
        )
    }
    ' \
  )"

  jq --argjson node "$node_json" '. + [$node]' "$TMP_JSON" > "$TMP_JSON.new" && mv "$TMP_JSON.new" "$TMP_JSON"

done < "$TMP_TXT"

node_tags="$(jq -r '.[].tag' "$TMP_JSON" | jq -R . | jq -s .)"

if [ -f "$OUT_CFG" ]; then
  jq \
    --slurpfile nodes "$TMP_JSON" \
    --argjson selector "$node_tags" \
    '
    .outbounds = (
      $nodes[0]
      + [
        { tag:"direct", protocol:"freedom" },
        { tag:"block", protocol:"blackhole" }
      ]
    )
    | .routing = (
        (.routing // { domainStrategy: "AsIs", rules: [] })
        | .domainStrategy = (.domainStrategy // "AsIs")
        | .balancers = (
            (.balancers // [])
            | map(
                if .tag == "b1" then
                  . + { selector: $selector, strategy: (.strategy // { type: "random" }) }
                else
                  .
                end
              )
            | if (map(.tag) | index("b1")) == null then
                . + [{ tag: "b1", selector: $selector, strategy: { type: "random" } }]
              else
                .
              end
          )
        | if (.rules // []) | length == 0 then
            .rules = [
              { type:"field", ip:["geoip:private"], outboundTag:"direct" },
              { type:"field", domain:["geosite:private"], outboundTag:"direct" },
              { type:"field", network:"tcp,udp", balancerTag:"b1" }
            ]
          else
            .
          end
      )
    ' "$OUT_CFG" > "$OUT_CFG.tmp"
  mv "$OUT_CFG.tmp" "$OUT_CFG"
else
  jq -n \
    --slurpfile nodes "$TMP_JSON" \
    --argjson selector "$node_tags" \
    '
    {
      log: { loglevel: "warning" },

      inbounds: [
        {
          tag: "socks-in",
          listen: "0.0.0.0",
          port: 1080,
          protocol: "socks",
          settings: { udp: true },
          sniffing: { enabled: true, destOverride: ["http","tls","quic"] }
        }
      ],

      outbounds: (
        $nodes[0]
        + [
          { tag:"direct", protocol:"freedom" },
          { tag:"block", protocol:"blackhole" }
        ]
      ),

      routing: {
        domainStrategy: "AsIs",
        balancers: [
          {
            tag: "b1",
            selector: $selector,
            strategy: { type: "random" }
          }
        ],
        rules: [
          { type:"field", ip:["geoip:private"], outboundTag:"direct" },
          { type:"field", domain:["geosite:private"], outboundTag:"direct" },
          { type:"field", network:"tcp,udp", balancerTag:"b1" }
        ]
      }
    }
    ' > "$OUT_CFG"
fi

echo "Wrote: $OUT_CFG"
echo "Nodes: $(jq length "$TMP_JSON")"

if [ -x /etc/init.d/xray ]; then
  /etc/init.d/xray restart || true
fi
