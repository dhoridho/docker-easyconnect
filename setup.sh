#!/usr/bin/env bash
set -e

INSTALL_DIR="${HOME}/Docker/EasyConnect"
DATA_DIR="${HOME}/.easyconnect-data"
ICON_PATH="${HOME}/.local/share/icons/easyconnect.png"
DESKTOP_PATH="${HOME}/.local/share/applications/easyconnect.desktop"
IMAGE="hagb/docker-easyconnect@sha256:40c411e71198111871ac281cee78ff0ae961139897674c7df8fa5eec0da78e80"
IMAGE_CLI="hagb/docker-easyconnect@sha256:2ffb7880436e25fb3764b64d18bd5418d81dc03b05899de68ff7c34b80e0363a"
SRC_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

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
sudo apt-get install -y xclip libnotify-bin desktop-file-utils

info "Writing config files..."
mkdir -p "${INSTALL_DIR}"

if [[ "${SRC_DIR}" != "${INSTALL_DIR}" ]]; then
  cp "${SRC_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
  cp "${SRC_DIR}/ec.sh" "${INSTALL_DIR}/ec.sh"
fi
chmod +x "${INSTALL_DIR}/ec.sh"

if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
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
  info "Created .env — fill in SVPN_HOST, VPN_USER, VPN_PASS, CLIP_TEXT"
else
  warning ".env exists — skipping (credentials preserved)"
fi

info "Installing ec..."
sudo ln -sf "${INSTALL_DIR}/ec.sh" /usr/local/bin/ec

info "Sudoers..."
echo "${USER} ALL=(ALL) NOPASSWD: /usr/sbin/iptables, /usr/sbin/ufw, /usr/sbin/ip, /usr/bin/ln" | sudo tee /etc/sudoers.d/easyconnect-iptables > /dev/null
sudo chmod 440 /etc/sudoers.d/easyconnect-iptables

if [[ ! -L /etc/resolv.conf ]] || [[ "$(readlink /etc/resolv.conf)" != "/run/systemd/resolve/resolv.conf" ]]; then
  warning "Fixing DNS — symlinking to systemd-resolved uplink..."
  sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
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
sed -i '/^alias ec=/d' "${HOME}/.bashrc"
sed -i '/alias easyconnect=/,/hagb\/docker-easyconnect/d' "${HOME}/.bashrc"
sed -i '/alias econnect-stop=/d' "${HOME}/.bashrc"
echo "alias ec=\"${INSTALL_DIR}/ec.sh\"" >> "${HOME}/.bashrc"

echo ""
echo -e "${GREEN}Done.${NC} Run: source ~/.bashrc && ec start"
echo "Edit ${INSTALL_DIR}/.env to set VPN credentials."
echo "First launch: enter your VPN URL, connect, then close the window to save credentials."
