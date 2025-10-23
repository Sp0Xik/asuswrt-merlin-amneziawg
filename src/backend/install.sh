#!/bin/sh
# AmneziaWG installer for Asuswrt-Merlin
# - Checks JFFS and Entware
# - Copies backend files
# - Sets up autorun
# - Mounts WebUI into router GUI
# Based on amneziawg-implementation-guide.md (install.sh section)

set -eu

LOG_TAG="amneziawg-installer"
REPO_ROOT="/jffs/amneziawg"
BACKEND_DIR="$REPO_ROOT/backend"
BIN_DIR="/opt/bin"
ETC_INITD="/opt/etc/init.d"
WWWD="/www"
WEBUI_SRC="$BACKEND_DIR/webui"
WEBUI_DST="$WWWD/UserLogin.asp_files/amneziawg"
START_SCRIPT="S99amneziawg"
STOP_SCRIPT="K01amneziawg"
SERVICE_NAME="amneziawg"

log() { logger -t "$LOG_TAG" "$@"; echo "$LOG_TAG: $@"; }
fail() { echo "Error: $1" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"; }

ensure_jffs() {
  [ -d /jffs ] || fail "/jffs not found. Enable JFFS in Asuswrt-Merlin (Administration > System)."
  [ -w /jffs ] || fail "/jffs not writable. Reboot or reformat JFFS and try again."
}

ensure_entware() {
  if [ ! -d /opt ] || [ ! -x /opt/bin/opkg ]; then
    fail "Entware not found. Install Entware first (amtm -> entware)."
  fi
  export PATH="/opt/sbin:/opt/bin:/opt/usr/bin:/sbin:/bin:/usr/sbin:/usr/bin:$PATH"
}

ensure_dirs() {
  mkdir -p "$REPO_ROOT" "$BACKEND_DIR" "$BIN_DIR" "$ETC_INITD"
}

copy_backend_files() {
  SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
  log "Source directory: $SRC_DIR"

  # Copy all backend payload
  mkdir -p "$BACKEND_DIR"
  cp -a "$SRC_DIR"/* "$BACKEND_DIR"/ 2>/dev/null || true

  # Ensure main binaries are executable if present
  for f in "$BACKEND_DIR"/*.sh "$BACKEND_DIR"/bin/*; do
    [ -e "$f" ] && chmod +x "$f" || true
  done
}

install_service_scripts() {
  cat >"$ETC_INITD/$START_SCRIPT" <<'EOF'
#!/bin/sh
# Start AmneziaWG backend
[ -f /opt/etc/default/amneziawg ] && . /opt/etc/default/amneziawg
BACKEND_DIR="/jffs/amneziawg/backend"
DAEMON="$BACKEND_DIR/awgd"
CONF_DIR="$BACKEND_DIR/conf"
PIDFILE="/opt/var/run/amneziawg.pid"

start() {
  mkdir -p "$(dirname "$PIDFILE")"
  if [ -x "$DAEMON" ]; then
    "$DAEMON" -c "$CONF_DIR" -p "$PIDFILE" &
  fi
}

stop() {
  [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null || true
}

case "$1" in
  start) start ;;
  stop) stop ;;
  restart) stop; sleep 1; start ;;
  *) start ;;
 esac
EOF
  chmod +x "$ETC_INITD/$START_SCRIPT"

  # Optional stop symlink for SysV order
  ln -sf "$ETC_INITD/$START_SCRIPT" "$ETC_INITD/$STOP_SCRIPT"
}

mount_webui() {
  # Create destination directory within Web UI static files
  mkdir -p "$WEBUI_DST"

  if [ -d "$WEBUI_SRC" ]; then
    # Bind mount keeps files isolated in JFFS but visible to httpd
    if ! mountpoint -q "$WEBUI_DST"; then
      mount -o bind "$WEBUI_SRC" "$WEBUI_DST" || fail "Bind mount failed for WebUI"
    fi
  else
    log "No webui directory found at $WEBUI_SRC; skipping WebUI mount"
  fi
}

setup_services() {
  # Ensure service autostarts via Entware init system
  if ! grep -q "$START_SCRIPT" /opt/etc/rc.unslung 2>/dev/null; then
    echo "/opt/etc/init.d/$START_SCRIPT start" >> /opt/etc/rc.unslung
  fi
}

post_install_notes() {
  log "Installation completed."
  log "Backend: $BACKEND_DIR"
  log "Service: /opt/etc/init.d/$START_SCRIPT"
  log "WebUI (bind-mounted): $WEBUI_DST"
}

main() {
  ensure_jffs
  ensure_entware
  ensure_dirs
  copy_backend_files
  install_service_scripts
  setup_services
  mount_webui || true
  post_install_notes
}

main "$@"
