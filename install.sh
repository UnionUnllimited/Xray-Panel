#!/bin/ash
# Xray-Panel installer for OpenWrt (ash). No bashisms.
# Installs: /usr/bin/xrayctl + skeleton dirs for SSH control panel.
# Safe by default: does not overwrite PassWall/Xray configs, does not replace xray binary.

set -eu

APP="xrayctl"
PREFIX_BIN="/usr/bin"
LIBEXEC_DIR="/usr/libexec/xray-panel"
ETC_DIR="/etc/xray-panel"
INITD_DIR="/etc/init.d"
BACKUP_DIR="/etc/xray-panel/backup"

REPO="${XRAY_PANEL_REPO:-UnionUnlllimited/Xray-Panel}"
BRANCH="${XRAY_PANEL_BRANCH:-main}"

log() { echo "[$APP] $*"; }
warn() { echo "[$APP] WARNING: $*" >&2; }
die() { echo "[$APP] ERROR: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Нет команды '$1'. Поставь пакет (обычно opkg install $1)"; }

is_openwrt() { [ -f /etc/openwrt_release ] || [ -f /etc/os-release ] && grep -qi openwrt /etc/os-release 2>/dev/null; }

detect_arch() {
  # Returns normalized arch label (not opkg arch).
  local m
  m="$(uname -m 2>/dev/null || echo unknown)"

  case "$m" in
    aarch64*|arm64*) echo "aarch64" ;;
    armv7*|armv7l*|armv7*) echo "armv7" ;;
    armv6*|armv6l*) echo "armv6" ;;
    mips64*) echo "mips64" ;;
    mipsel*|mipsle*) echo "mipsle" ;;
    mips*) echo "mips" ;;
    x86_64|amd64) echo "x86_64" ;;
    i386|i486|i586|i686) echo "x86" ;;
    *) echo "unknown:$m" ;;
  esac
}

backup_file() {
  # backup_file /path/to/file
  local f="$1"
  [ -e "$f" ] || return 0
  mkdir -p "$BACKUP_DIR"
  local ts
  ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
  local base
  base="$(echo "$f" | sed 's#/#_#g')"
  cp -a "$f" "$BACKUP_DIR/${base}.${ts}.bak" 2>/dev/null || true
}

detect_passwall() {
  # Heuristic: init scripts or uci sections.
  if [ -x /etc/init.d/passwall ] || [ -x /etc/init.d/passwall2 ]; then
    echo "yes"; return
  fi
  if command -v uci >/dev/null 2>&1; then
    uci show passwall >/dev/null 2>&1 && { echo "yes"; return; }
    uci show passwall2 >/dev/null 2>&1 && { echo "yes"; return; }
  fi
  echo "no"
}

detect_xray() {
  if command -v xray >/dev/null 2>&1; then echo "yes"; else echo "no"; fi
}

safe_install_notes() {
  local pw xray
  pw="$(detect_passwall)"
  xray="$(detect_xray)"

  log "OpenWrt: $(is_openwrt && echo yes || echo no)"
  log "Arch: $(detect_arch)"
  log "PassWall: $pw"
  log "Xray binary: $xray"

  if [ "$pw" = "yes" ]; then
    warn "Обнаружен PassWall. Инсталлер НЕ будет менять его конфиги/iptables/uci."
  fi
  if [ "$xray" = "yes" ]; then
    warn "Обнаружен xray. Инсталлер НЕ будет заменять бинарник и НЕ будет трогать /etc/xray/*."
  fi
}

install_dirs() {
  mkdir -p "$PREFIX_BIN" "$LIBEXEC_DIR" "$ETC_DIR" "$BACKUP_DIR" "/var/log"
}

install_xrayctl() {
  local target="$PREFIX_BIN/$APP"

  # Backup old binary/script if exists
  backup_file "$target"

  cat >"$target" <<'EOF'
#!/bin/ash
set -eu

APP="xrayctl"
LIBEXEC_DIR="/usr/libexec/xray-panel"
ETC_DIR="/etc/xray-panel"
LOG="/var/log/xray-panel.log"

log() { echo "[$APP] $*"; }
warn() { echo "[$APP] WARNING: $*" >&2; }
die() { echo "[$APP] ERROR: $*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

status_xray() {
  if have pgrep && pgrep -x xray >/dev/null 2>&1; then
    log "xray: RUNNING"
  else
    log "xray: not running"
  fi
  if have xray; then
    # xray version output varies; keep it simple
    xray version 2>/dev/null || true
  else
    warn "xray binary not found in PATH"
  fi
}

menu() {
  while true; do
    echo
    echo "=== Xray SSH Control Panel (skeleton) ==="
    echo "1) Status"
    echo "2) Show configs (paths)"
    echo "3) Tail logs"
    echo "4) Exit"
    printf "> "
    read -r ans || exit 0
    case "$ans" in
      1) status_xray ;;
      2)
        echo "Config dirs:"
        echo "  /etc/xray (PassWall/Xray may use this)"
        echo "  $ETC_DIR (xray-panel)"
        ;;
      3)
        if [ -f "$LOG" ]; then
          tail -n 80 "$LOG" 2>/dev/null || true
        else
          warn "No $LOG yet"
        fi
        ;;
      4|q|quit|exit) exit 0 ;;
      *) echo "Unknown option" ;;
    esac
  done
}

usage() {
  cat <<USAGE
Usage:
  xrayctl menu            # SSH control panel (interactive)
  xrayctl status          # show xray status + version
  xrayctl doctor          # quick diagnostics
  xrayctl help

Env:
  (none)
USAGE
}

doctor() {
  log "doctor: basic checks"
  echo "uname -m: $(uname -m 2>/dev/null || echo n/a)"
  echo "openwrt:  $( [ -f /etc/openwrt_release ] && echo yes || echo no )"
  echo "passwall: $( [ -x /etc/init.d/passwall ] || [ -x /etc/init.d/passwall2 ] && echo maybe || echo no )"
  echo "xray:     $( have xray && echo yes || echo no )"
  echo "curl:     $( have curl && echo yes || echo no )"
  echo "ubus:     $( have ubus && echo yes || echo no )"
}

cmd="${1:-help}"
case "$cmd" in
  menu) menu ;;
  status) status_xray ;;
  doctor) doctor ;;
  help|-h|--help) usage ;;
  *) die "Unknown command: $cmd (try: xrayctl help)" ;;
esac
EOF

  chmod 0755 "$target"
  log "Installed $target"
}

install_profile_hint() {
  # Optional: add a MOTD hint for SSH users (non-invasive).
  local motd="/etc/banner"
  if [ -f "$motd" ] && ! grep -q "xrayctl menu" "$motd" 2>/dev/null; then
    backup_file "$motd"
    {
      echo ""
      echo "Tip: run 'xrayctl menu' for SSH control panel"
    } >>"$motd" 2>/dev/null || true
  fi
}

main() {
  need_cmd mkdir
  need_cmd sed
  need_cmd uname
  # curl is not strictly required for this skeleton installer, but user uses curl anyway.
  safe_install_notes

  install_dirs
  install_xrayctl
  install_profile_hint

  log "Done."
  log "Run: xrayctl menu"
  log "Repo context: $REPO ($BRANCH)"
}

main "$@"
