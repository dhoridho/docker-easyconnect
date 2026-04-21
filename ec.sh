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

cmd="${1:-help}"

case "$cmd" in
  start)
    if _is_running; then
      if _vpn_connected; then
        notify-send "EasyConnect" "Already running — VPN connected." --icon=network-vpn 2>/dev/null || true
        echo "already running — VPN connected"
      else
        notify-send "EasyConnect" "Already running — not connected yet." --icon=network-vpn 2>/dev/null || true
        echo "already running — not connected yet"
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
