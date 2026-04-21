#!/usr/bin/env bash
set -e

INSTALL_DIR="${HOME}/Docker/EasyConnect"
DATA_DIR="${HOME}/.easyconnect-data"
ICON_PATH="${HOME}/.local/share/icons/easyconnect.png"
DESKTOP_PATH="${HOME}/.local/share/applications/easyconnect.desktop"
BASHRC="${HOME}/.bashrc"
IMAGE="hagb/docker-easyconnect@sha256:40c411e71198111871ac281cee78ff0ae961139897674c7df8fa5eec0da78e80"
IMAGE_CLI="hagb/docker-easyconnect@sha256:2ffb7880436e25fb3764b64d18bd5418d81dc03b05899de68ff7c34b80e0363a"
ROUTER_IP=$(ip route show default | awk '/default/ {print $3; exit}')
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $*"; }
warning() { echo -e "${YELLOW}[!]${NC} $*"; }

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found. Install: https://docs.docker.com/engine/install/"
  exit 1
fi

if ! docker compose version &>/dev/null; then
  echo "ERROR: docker compose plugin not found."
  exit 1
fi

info "TUN module..."
if [[ ! -e /dev/net/tun ]]; then
  sudo modprobe tun
fi

info "Dependencies..."
sudo apt-get install -y xclip libnotify-bin &>/dev/null

info "Writing config files..."
mkdir -p "${INSTALL_DIR}"

cat > "${INSTALL_DIR}/docker-compose.yml" <<'EOF'
services:
  easyconnect:
    image: ${IMAGE:-hagb/docker-easyconnect:latest}
    container_name: easyconnect
    network_mode: host
    restart: "no"
    stop_grace_period: 5s
    devices:
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    environment:
      - DISPLAY=${DISPLAY:-:0}
      - QT_QPA_PLATFORM=xcb
      - EXIT=1
      - CLIP_TEXT=${CLIP_TEXT}
    volumes:
      - /tmp/.X11-unix:/tmp/.X11-unix:rw
      - ${DATA_DIR:-~/.easyconnect-data}:/root/conf

  easyconnect-cli:
    image: ${IMAGE_CLI:-hagb/docker-easyconnect:cli}
    container_name: easyconnect
    network_mode: host
    restart: "no"
    stop_grace_period: 5s
    devices:
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    environment:
      - EXIT=1
      - CLI_OPTS=-d ${SVPN_HOST} -u ${VPN_USER} -p ${VPN_PASS}
    volumes:
      - ${DATA_DIR:-~/.easyconnect-data}:/root/conf
    profiles:
      - cli
EOF

cat > "${INSTALL_DIR}/.env" <<EOF
DISPLAY=:0
DATA_DIR=${DATA_DIR}
IMAGE=${IMAGE}
IMAGE_CLI=${IMAGE_CLI}

SVPN_HOST=
VPN_USER=
VPN_PASS=
CLIP_TEXT=
EOF

cp "${BASH_SOURCE[0]%/*}/ec.sh" "${INSTALL_DIR}/ec.sh"
chmod +x "${INSTALL_DIR}/ec.sh"

info "Installing ec..."
sudo ln -sf "${INSTALL_DIR}/ec.sh" /usr/local/bin/ec

info "Sudoers..."
echo "${USER} ALL=(ALL) NOPASSWD: /usr/sbin/iptables, /usr/sbin/ufw, /usr/bin/tee /etc/resolv.conf, /usr/sbin/ip" | sudo tee /etc/sudoers.d/easyconnect-iptables > /dev/null
sudo chmod 440 /etc/sudoers.d/easyconnect-iptables

if grep -q "127.0.0.53" /etc/resolv.conf 2>/dev/null; then
  warning "systemd-resolved detected, fixing DNS..."
  sudo rm -f /etc/resolv.conf
  { echo "nameserver 1.1.1.1"; echo "nameserver ${ROUTER_IP}"; } | sudo tee /etc/resolv.conf > /dev/null
fi

info "Pulling image and extracting icon..."
docker pull "${IMAGE}" --quiet
mkdir -p "${HOME}/.local/share/icons"
TMP_CTR=$(docker create "${IMAGE}")
docker cp "${TMP_CTR}:/usr/share/sangfor/EasyConnect/resources/EasyConnect.png" "${ICON_PATH}"
docker rm "${TMP_CTR}" > /dev/null

info "Desktop entry..."
find "${HOME}/.local/share/applications" -iname "*easyconnect*" -not -path "${DESKTOP_PATH}" -delete 2>/dev/null || true
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

info "Shell alias..."
sed -i '/^alias ec=/d' "${BASHRC}"
sed -i '/alias easyconnect=/,/hagb\/docker-easyconnect/d' "${BASHRC}"
sed -i '/alias econnect-stop=/d' "${BASHRC}"
echo "alias ec=\"${INSTALL_DIR}/ec.sh\"" >> "${BASHRC}"

echo ""
echo -e "${GREEN}Done.${NC} Run: source ~/.bashrc && ec start"
echo "Fill in SVPN_HOST, VPN_USER, VPN_PASS, CLIP_TEXT in ${INSTALL_DIR}/.env"
echo "First launch: enter your VPN URL, connect, then close the window to save credentials."
