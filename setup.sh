#!/usr/bin/env bash
set -e

INSTALL_DIR="${HOME}/Docker/EasyConnect"
DATA_DIR="${HOME}/.easyconnect-data"
ICON_PATH="${HOME}/.local/share/icons/easyconnect.png"
DESKTOP_PATH="${HOME}/.local/share/applications/easyconnect.desktop"
BASHRC="${HOME}/.bashrc"
IMAGE="hagb/docker-easyconnect@sha256:40c411e71198111871ac281cee78ff0ae961139897674c7df8fa5eec0da78e80"
ROUTER_IP=$(ip route show default | awk '/default/ {print $3; exit}')
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $*"; }
warning() { echo -e "${YELLOW}[!]${NC} $*"; }

# ── 1. Dependencies ──────────────────────────────────────────────────────────
info "Checking dependencies..."

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found. Install Docker first: https://docs.docker.com/engine/install/"
  exit 1
fi

if ! docker compose version &>/dev/null; then
  echo "ERROR: docker compose plugin not found."
  exit 1
fi

# ── 2. TUN module ────────────────────────────────────────────────────────────
info "Loading TUN kernel module..."
if [[ ! -e /dev/net/tun ]]; then
  sudo modprobe tun
  info "TUN module loaded."
else
  info "TUN already available."
fi

# ── 3. Create install directory ───────────────────────────────────────────────
info "Creating install directory at ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"

# ── 4. Write docker-compose.yml ───────────────────────────────────────────────
info "Writing docker-compose.yml..."
cat > "${INSTALL_DIR}/docker-compose.yml" <<'EOF'
services:
  easyconnect:
    image: ${IMAGE:-hagb/docker-easyconnect:latest}
    container_name: easyconnect
    network_mode: host
    restart: "no"
    devices:
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    environment:
      - DISPLAY=${DISPLAY:-:0}
      - QT_QPA_PLATFORM=xcb
      - EXIT=1
    volumes:
      - /tmp/.X11-unix:/tmp/.X11-unix:rw
      - ${DATA_DIR:-~/.easyconnect-data}:/root/conf
EOF

# ── 5. Write .env ─────────────────────────────────────────────────────────────
info "Writing .env..."
cat > "${INSTALL_DIR}/.env" <<EOF
DISPLAY=:0
DATA_DIR=${DATA_DIR}
IMAGE=${IMAGE}
EOF

# ── 6. Write ec.sh ───────────────────────────────────────────────────────────
info "Writing ec.sh..."
cat > "${INSTALL_DIR}/ec.sh" <<EOF
#!/usr/bin/env bash
set -e

COMPOSE_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="\${HOME}/.easyconnect-data"

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

_compose() {
  docker compose --env-file "\${COMPOSE_DIR}/.env" -f "\${COMPOSE_DIR}/docker-compose.yml" "\$@"
}

cmd="\${1:-help}"

case "\$cmd" in
  start)
    _require_tun
    _xhost_allow
    mkdir -p "\$DATA_DIR"
    _compose up -d
    echo "EasyConnect started."
    ;;

  stop)
    _compose down
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
    mkdir -p "\$DATA_DIR"
    _compose down
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
EOF

chmod +x "${INSTALL_DIR}/ec.sh"

# ── 7. System-wide ec command ─────────────────────────────────────────────────
info "Installing ec to /usr/local/bin..."
sudo ln -sf "${INSTALL_DIR}/ec.sh" /usr/local/bin/ec

# ── 8. Passwordless sudo for iptables (needed for cleanup on VPN disconnect) ──
info "Configuring passwordless sudo for iptables..."
echo "${USER} ALL=(ALL) NOPASSWD: /usr/sbin/iptables, /usr/sbin/ufw, /usr/bin/tee /etc/resolv.conf" | sudo tee /etc/sudoers.d/easyconnect-iptables > /dev/null
sudo chmod 440 /etc/sudoers.d/easyconnect-iptables
info "Done."

# ── 8. Fix DNS (bypass systemd-resolved) ─────────────────────────────────────
if grep -q "127.0.0.53" /etc/resolv.conf 2>/dev/null; then
  warning "systemd-resolved detected. Fixing DNS to use 1.1.1.1 / ${ROUTER_IP}..."
  sudo rm -f /etc/resolv.conf
  echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
  echo "nameserver ${ROUTER_IP}" | sudo tee -a /etc/resolv.conf > /dev/null
  info "DNS fixed."
else
  info "DNS looks fine, skipping."
fi

# ── 8. Extract icon from image ────────────────────────────────────────────────
info "Pulling image and extracting icon..."
docker pull "${IMAGE}" --quiet
mkdir -p "${HOME}/.local/share/icons"
TMP_CTR=$(docker create "${IMAGE}")
docker cp "${TMP_CTR}:/usr/share/sangfor/EasyConnect/resources/EasyConnect.png" "${ICON_PATH}"
docker rm "${TMP_CTR}" > /dev/null

# ── 9. Remove old desktop entries ────────────────────────────────────────────
info "Cleaning up old EasyConnect desktop entries..."
find "${HOME}/.local/share/applications" -iname "*easyconnect*" -not -path "${DESKTOP_PATH}" -delete 2>/dev/null || true

# ── 10. Create desktop entry ──────────────────────────────────────────────────
info "Creating desktop entry..."
mkdir -p "${HOME}/.local/share/applications"
cat > "${DESKTOP_PATH}" <<EOF
[Desktop Entry]
Name=EasyConnect
Comment=Sangfor EasyConnect VPN
Exec=${INSTALL_DIR}/ec.sh start
Icon=${ICON_PATH}
Type=Application
Categories=Network;VPN;
Keywords=vpn;easyconnect;sangfor;
StartupNotify=false
EOF

update-desktop-database "${HOME}/.local/share/applications/" 2>/dev/null || true

# ── 11. Add shell alias ───────────────────────────────────────────────────────
ALIAS_LINE="alias ec=\"${INSTALL_DIR}/ec.sh\""

# Remove all existing ec alias lines first, then add once
sed -i '/^alias ec=/d' "${BASHRC}"
echo "" >> "${BASHRC}"
echo "${ALIAS_LINE}" >> "${BASHRC}"
info "Set 'ec' alias in ${BASHRC}."

# ── 12. Remove old EasyConnect aliases from bashrc ───────────────────────────
if grep -q "easyconnect\|econnect\|hagb\|easyConnect" "${BASHRC}" 2>/dev/null; then
  warning "Old EasyConnect entries found in ${BASHRC}, removing..."
  sed -i '/alias easyconnect=/,/hagb\/docker-easyconnect/d' "${BASHRC}"
  sed -i '/alias econnect-stop=/d' "${BASHRC}"
  sed -i '/alias easyconnect=.*easyConnect/d' "${BASHRC}"
  info "Old aliases removed."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "  Run:  source ~/.bashrc"
echo "  Then: ec start"
echo "  Or:   search 'EasyConnect' in your app launcher"
echo ""
echo "  First launch: enter your company VPN URL, login, close window to save credentials."
