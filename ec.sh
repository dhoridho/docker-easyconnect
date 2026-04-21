#!/usr/bin/env bash
set -e

COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.easyconnect-data"

_require_tun() {
  if [[ ! -e /dev/net/tun ]]; then
    echo "ERROR: /dev/net/tun missing. Load tun module:"
    echo "  sudo modprobe tun"
    exit 1
  fi
}

_xhost_allow() {
  xhost +local:docker &>/dev/null || true
}

_cleanup_iptables() {
  echo "Cleaning up EasyConnect iptables rules..."
  sudo iptables -F
  sudo iptables -X
  sudo iptables -t nat -F
  sudo iptables -t nat -X
  sudo iptables -t mangle -F
  sudo iptables -t mangle -X
  sudo ufw reload &>/dev/null
  echo "iptables cleaned."
}

_compose() {
  docker compose --env-file "${COMPOSE_DIR}/.env" -f "${COMPOSE_DIR}/docker-compose.yml" "$@"
}

cmd="${1:-help}"

case "$cmd" in
  start)
    _require_tun
    _xhost_allow
    mkdir -p "$DATA_DIR"
    _compose up -d
    echo "EasyConnect started."
    # watch for container exit and clean up iptables automatically
    (docker wait easyconnect &>/dev/null && _cleanup_iptables) &
    disown
    ;;

  stop)
    _compose down
    _cleanup_iptables
    echo "EasyConnect stopped."
    ;;

  restart)
    _require_tun
    _xhost_allow
    _compose restart
    echo "EasyConnect restarted."
    ;;

  logs)
    _compose logs -f
    ;;

  status)
    _compose ps
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
    echo "EasyConnect recreated."
    ;;

  help|*)
    echo "Usage: ec.sh <command>"
    echo ""
    echo "  start     — allow X11, create data dir, start container"
    echo "  stop      — stop and remove container"
    echo "  restart   — restart container"
    echo "  recreate  — full stop + fresh start (keeps data)"
    echo "  logs      — follow container logs"
    echo "  status    — show container status"
    echo "  shell     — exec bash inside container"
    echo "  pull      — pull latest image"
    ;;
esac
