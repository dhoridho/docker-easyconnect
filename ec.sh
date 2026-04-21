#!/usr/bin/env bash
set -e

COMPOSE_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DATA_DIR="${HOME}/.easyconnect-data"

_require_tun() {
  if [[ ! -e /dev/net/tun ]]; then
    echo "ERROR: /dev/net/tun missing. Run: sudo modprobe tun"
    exit 1
  fi
}

_xhost_allow() {
  xhost +local:docker &>/dev/null || true
}

_cleanup_iptables() {
  sudo iptables -F 2>/dev/null || true
  sudo iptables -X 2>/dev/null || true
  sudo iptables -t nat -F 2>/dev/null || true
  sudo iptables -t nat -X 2>/dev/null || true
  sudo iptables -t mangle -F 2>/dev/null || true
  sudo iptables -t mangle -X 2>/dev/null || true
  sudo ufw reload &>/dev/null || true
  ip link show tun0 &>/dev/null && sudo ip link delete tun0 2>/dev/null || true
  local router
  router=$(ip route show default | awk '/default/ {print $3; exit}')
  if [[ -n "$router" ]]; then
    { echo "nameserver 1.1.1.1"; echo "nameserver ${router}"; } | sudo tee /etc/resolv.conf > /dev/null
  fi
}

_compose() {
  docker compose --env-file "${COMPOSE_DIR}/.env" -f "${COMPOSE_DIR}/docker-compose.yml" "$@"
}

_is_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' easyconnect 2>/dev/null)" == "true" ]]
}

_vpn_connected() {
  ip link show tun0 &>/dev/null
}

_keepalive() {
  local host ping_ok=1
  host=$(grep '^SVPN_HOST=' "${COMPOSE_DIR}/.env" | cut -d= -f2- | sed 's|https\?://||' | cut -d: -f1 | cut -d/ -f1)
  [[ -z "$host" ]] && return
  echo $BASHPID > /tmp/easyconnect-keepalive.pid
  export DISPLAY="${DISPLAY:-:0}"
  while _is_running; do
    if _vpn_connected; then
      if ping -c 1 -W 3 "$host" &>/dev/null; then
        ping_ok=1
      elif [[ $ping_ok -eq 1 ]]; then
        notify-send -u normal "EasyConnect" "Keepalive ping failed — VPN may be unstable." 2>/dev/null || true
        ping_ok=0
      fi
    fi
    sleep 60
  done
  rm -f /tmp/easyconnect-keepalive.pid
}

_watch_disconnect() {
  local was_connected=0
  local clip
  clip=$(grep '^CLIP_TEXT=' "${COMPOSE_DIR}/.env" | cut -d= -f2-)
  export DISPLAY="${DISPLAY:-:0}"
  while _is_running; do
    if _vpn_connected; then
      was_connected=1
    elif [[ $was_connected -eq 1 ]]; then
      if [[ -n "$clip" ]]; then
        action=$(notify-send -u critical "EasyConnect" "VPN disconnected — Re-Login required." --action="copy=Copy Password" --wait 2>/dev/null)
        [[ "$action" == "copy" ]] && echo -n "$clip" | xclip -selection clipboard 2>/dev/null || true
      else
        notify-send -u critical "EasyConnect" "VPN disconnected — Re-Login required." 2>/dev/null || true
      fi
      was_connected=0
    fi
    sleep 5
  done
}

cmd="${1:-help}"

case "$cmd" in
  start)
    if _is_running; then
      if _vpn_connected; then
        notify-send "EasyConnect" "Already running — VPN connected." --icon=network-vpn 2>/dev/null || true
        echo "already running — VPN connected"
      else
        notify-send "EasyConnect" "Already running — not connected. Re-Login may be required in the app." --icon=network-vpn 2>/dev/null || true
        echo "already running — not connected (Re-Login may be required in the app)"
      fi
      exit 0
    fi
    _require_tun
    _xhost_allow
    mkdir -p "$DATA_DIR"
    _compose up -d easyconnect
    clip=$(grep '^CLIP_TEXT=' "${COMPOSE_DIR}/.env" | cut -d= -f2-)
    if [[ -n "$clip" ]]; then
      echo -n "$clip" | xclip -selection clipboard 2>/dev/null || true
    fi
    echo "started (GUI)"
    (docker wait easyconnect &>/dev/null && _cleanup_iptables) &
    disown
    (_keepalive) &
    disown
    (_watch_disconnect) &
    disown
    ;;

  cli)
    if _is_running; then
      echo "already running — stop it first with: ec stop"
      exit 1
    fi
    _require_tun
    mkdir -p "$DATA_DIR"
    _compose --profile cli up -d easyconnect-cli
    echo "started (CLI)"
    (docker wait easyconnect &>/dev/null && _cleanup_iptables) &
    disown
    ;;

  stop)
    if ! _is_running; then
      echo "not running"
      exit 0
    fi
    _compose down
    _cleanup_iptables
    echo "stopped"
    ;;

  restart)
    _require_tun
    _xhost_allow
    _compose restart
    echo "restarted"
    ;;

  logs)
    _compose logs -f
    ;;

  status)
    _compose ps
    _vpn_connected && echo "VPN: connected" || echo "VPN: not connected"
    if [[ -f /tmp/easyconnect-keepalive.pid ]] && kill -0 "$(cat /tmp/easyconnect-keepalive.pid)" 2>/dev/null; then
      echo "Keepalive: running (pid $(cat /tmp/easyconnect-keepalive.pid))"
    else
      echo "Keepalive: not running"
    fi
    ;;

  shell)
    docker exec -it easyconnect /bin/bash
    ;;

  pull)
    _compose pull
    ;;

  recreate)
    _require_tun
    _xhost_allow
    mkdir -p "$DATA_DIR"
    _compose down
    _cleanup_iptables
    _compose up -d --force-recreate
    echo "recreated"
    ;;

  help|*)
    echo "usage: ec <command>"
    echo ""
    echo "  start     start VPN (GUI)"
    echo "  cli       start VPN (headless, uses credentials from .env)"
    echo "  stop      stop VPN"
    echo "  restart   restart container"
    echo "  recreate  stop, clean, restart (keeps data)"
    echo "  status    container + VPN status"
    echo "  logs      follow logs"
    echo "  shell     bash inside container"
    echo "  pull      pull latest image"
    ;;
esac
