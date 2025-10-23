#!/bin/sh
# api.sh — Core REST-like shell API for AmneziaWG backend
# Provides endpoints for settings, peers, status, and policy routing.
# Source: consolidated from amneziawg-backend-api.md and amneziawg-routing-ui.md

set -e

API_VERSION="1"
DATA_DIR="/jffs/amneziawg"
CFG_DIR="$DATA_DIR/config"
RUNTIME_DIR="/tmp/amneziawg"
ROUTES_FILE="$CFG_DIR/policy_routes.json"
PEERS_FILE="$CFG_DIR/peers.json"
WG_IF="awgvpn0"

mkdir -p "$CFG_DIR" "$RUNTIME_DIR"

# Utilities
j() { command -v jq >/dev/null 2>&1 && jq -c "$@" || cat; }
json_ok() { printf '{"ok":true,"data":%s}\n' "${1:-null}"; }
json_err() { msg="$1"; code="${2:-1}"; printf '{"ok":false,"error":"%s","code":%s}\n' "$(printf %s "$msg" | sed 's/"/\\"/g')" "$code"; exit "$code"; }
read_all() { cat; }

ensure_file() { f="$1"; d=$(dirname "$f"); [ -d "$d" ] || mkdir -p "$d"; [ -f "$f" ] || echo '{}' >"$f"; }
read_json_file() { f="$1"; ensure_file "$f"; cat "$f" | j '.'; }
write_json_file() { f="$1"; tmp="$f.tmp"; cat >"$tmp" && mv "$tmp" "$f"; }

# System helpers
wg_running() { ip link show "$WG_IF" >/dev/null 2>&1; }
reload_firewall() { service firewall restart >/dev/null 2>&1 || true; }
restart_wg() { service amneziawg restart >/dev/null 2>&1 || true; }

# Routing helpers
mark_table_from_id() { id="$1"; echo $((10000 + id)); }
fwmark_from_id() { id="$1"; echo $((0xA000 + id)); }

# API: General
api_ping() { json_ok '{"pong":true,"version":"'"$API_VERSION"'"}'; }
api_status() {
  state="down"; wg_running && state="up";
  pub_ip=$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || echo null)
  json_ok "$(printf '{"iface":"%s","state":"%s","public_ip":%s}' "$WG_IF" "$state" "$( [ "$pub_ip" = null ] && echo null || printf '"%s"' "$pub_ip")")"
}

# API: Peers
api_list_peers() { read_json_file "$PEERS_FILE" | j '.' | json_ok "$(cat)"; }
api_get_peer() { id="$1"; [ -n "$id" ] || json_err "peer id required" 400; read_json_file "$PEERS_FILE" | j ".peers[] | select(.id==\"$id\")" | {
  read line || true; [ -n "$line" ] || json_err "peer not found" 404; json_ok "$line"; }
}
api_save_peers() { body=$(read_all); echo "$body" | j '.' >/dev/null 2>&1 || json_err "invalid JSON" 400; echo "$body" | write_json_file "$PEERS_FILE"; restart_wg; json_ok '{}'; }

# API: Settings (basic)
SET_FILE="$CFG_DIR/settings.json"
api_get_settings() { read_json_file "$SET_FILE" | json_ok "$(cat)"; }
api_save_settings() { body=$(read_all); echo "$body" | j '.' >/dev/null 2>&1 || json_err "invalid JSON" 400; echo "$body" | write_json_file "$SET_FILE"; restart_wg; json_ok '{}'; }

# Policy Routing schema stored in ROUTES_FILE as {"rules":[ ... ]}
# Rule fields: id(int), name(str), enabled(bool), match:{src,cidrs,ports,proto,uid,gid,ifname,dns_domains[]}, action:{via:intf|gateway, table:int, priority:int}

api_get_policy_rules() { ensure_file "$ROUTES_FILE"; read_json_file "$ROUTES_FILE" | json_ok "$(cat)"; }

api_set_policy_rules() {
  body=$(read_all)
  echo "$body" | j '.' >/dev/null 2>&1 || json_err "invalid JSON" 400
  echo "$body" | write_json_file "$ROUTES_FILE"
  api_apply_policy_rules silent
  json_ok '{}'
}

api_apply_policy_rules() {
  # Flush existing policy rules/tables managed by us
  # We use fwmark 0xA000-0xAFFF and tables 10000-10999
  for tid in $(seq 10000 10999); do ip rule del table $tid 2>/dev/null || true; done
  ip -4 route flush table main 2>/dev/null || true
  ip -4 route flush cache 2>/dev/null || true

  cfg=$(read_json_file "$ROUTES_FILE")
  echo "$cfg" | j -r '.rules[]? | @base64' 2>/dev/null | while read -r enc; do
    rule=$(echo "$enc" | base64 -d)
    enabled=$(echo "$rule" | j -r '.enabled // true')
    [ "$enabled" = "true" ] || continue
    rid=$(echo "$rule" | j -r '.id // 0')
    name=$(echo "$rule" | j -r '.name // ("rule-"+(.id|tostring))')
    prio=$(echo "$rule" | j -r '.action.priority // 10000')
    table=$(echo "$rule" | j -r '.action.table // empty')
    via_if=$(echo "$rule" | j -r '.action.via // empty')
    gw=$(echo "$rule" | j -r '.action.gateway // empty')

    [ -n "$table" ] || table=$(mark_table_from_id "$rid")

    # Ensure table has default route
    if [ -n "$via_if" ]; then
      dev="$via_if"
      ip -4 route flush table "$table" 2>/dev/null || true
      ip -4 route add default dev "$dev" table "$table" 2>/dev/null || true
    elif [ -n "$gw" ]; then
      ip -4 route flush table "$table" 2>/dev/null || true
      ip -4 route add default via "$gw" table "$table" 2>/dev/null || true
    fi

    # Build selectors
    src=$(echo "$rule" | j -r '.match.src // empty')
    ifname=$(echo "$rule" | j -r '.match.ifname // empty')
    proto=$(echo "$rule" | j -r '.match.proto // empty')
    uid=$(echo "$rule" | j -r '.match.uid // empty')
    gid=$(echo "$rule" | j -r '.match.gid // empty')

    # ip rule add ... supports from, fwmark, uidrange, sport/dport via nft/iptables normally.
    # For simplicity, support from and uid.

    cmd="ip rule add prio $prio table $table"
    [ -n "$src" ] && cmd="$cmd from $src"
    [ -n "$uid" ] && cmd="$cmd uidrange $uid-$uid"
    # ifname/proto/ports would require nftables marks; left as future work.

    sh -c "$cmd" 2>/dev/null || true
  done

  reload_firewall
  [ "$1" = silent ] || json_ok '{"applied":true}'
}

api_reset_policy_rules() {
  : >"$ROUTES_FILE"
  echo '{"rules":[]}' >"$ROUTES_FILE"
  api_apply_policy_rules silent
  json_ok '{}'
}

# Dispatch
usage() {
  cat <<EOF
amneziawg api v$API_VERSION
Usage: $0 <endpoint> [args]
Endpoints:
  ping
  status
  settings.get
  settings.save <json>
  peers.list
  peers.get <id>
  peers.save <json>
  policy.get
  policy.set <json>
  policy.apply
  policy.reset
EOF
}

endpoint="$1"; shift || true
case "$endpoint" in
  ping) api_ping ;;
  status) api_status ;;
  settings.get) api_get_settings ;;
  settings.save)
    if [ -n "$1" ]; then printf %s "$1" | api_save_settings; else read_all | api_save_settings; fi ;;
  peers.list) api_list_peers ;;
  peers.get) api_get_peer "$1" ;;
  peers.save)
    if [ -n "$1" ]; then printf %s "$1" | api_save_peers; else read_all | api_save_peers; fi ;;
  policy.get) api_get_policy_rules ;;
  policy.set)
    if [ -n "$1" ]; then printf %s "$1" | api_set_policy_rules; else read_all | api_set_policy_rules; fi ;;
  policy.apply) api_apply_policy_rules ;;
  policy.reset) api_reset_policy_rules ;;
  ''|help|-h|--help) usage ;;
  *) json_err "unknown endpoint" 404 ;;
 esac
