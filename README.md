# docker-easyconnect

Sangfor EasyConnect VPN in Docker with X11 GUI, persistent credentials, automatic clipboard fill, and iptables cleanup on disconnect.

## Requirements

- Docker + Docker Compose
- X11 display server
- `xclip` and `libnotify-bin` (installed by `setup.sh`)
- `sudo modprobe tun` if `/dev/net/tun` is missing

## Setup

```bash
git clone https://github.com/dhoridho/docker-easyconnect
cd docker-easyconnect
bash setup.sh
source ~/.bashrc
```

Edit `~/Docker/EasyConnect/.env` and fill in your credentials:

```
SVPN_HOST=https://vpn.company.com/
VPN_USER=youruser
VPN_PASS=yourpassword
CLIP_TEXT=yourpassword
```

First launch: enter your company VPN URL, connect, close the window. Credentials save to `~/.easyconnect-data` on exit.

## Usage

```bash
ec start      # start VPN (GUI)
ec stop       # stop VPN
ec status     # container + VPN connection status
ec restart    # restart container
ec recreate   # full stop + fresh start (keeps credentials)
ec logs       # follow logs
ec shell      # bash inside container
ec pull       # pull latest image
```

`ec` is installed to `/usr/local/bin` — works from anywhere, no shell alias needed.

## How it works

**GUI close stops the container** — `EXIT=1` breaks EasyConnect's internal restart loop. Closing the window exits cleanly instead of looping forever.

**Clipboard auto-fill** — if `CLIP_TEXT` is set in `.env`, `ec start` copies it to the host clipboard automatically. Paste into the VPN password field on first connection.

**iptables cleanup on disconnect** — EasyConnect adds iptables rules on connect that survive container stop. `ec stop` (and the background watcher on window close) flushes all rules and reloads UFW automatically. Also deletes `tun0` if still up.

**DNS** — `systemd-resolved` conflicts with EasyConnect. `setup.sh` replaces `/etc/resolv.conf` with a static file using `1.1.1.1` + your router gateway. Avoid `8.8.8.8` — EasyConnect routes it through `tun0`, breaking DNS when VPN is down. On disconnect, DNS is re-detected from the current network's default route.

**Credentials** — saved to `~/.easyconnect-data` which maps to `/root/conf` inside the container (not `/root/.easyconnect` — common mistake).

**Image** — pinned to a specific digest. To upgrade, pull a new image, update `IMAGE` in `.env`, run `ec recreate`.

## CLI mode

A headless CLI service is included (`ec cli`) using `hagb/docker-easyconnect:cli`. It reads `SVPN_HOST`, `VPN_USER`, and `VPN_PASS` from `.env`. However, the server-side `enableautologin=0` flag and CAPTCHA gate block automated login — CLI mode will connect the VPN tunnel but cannot authenticate without manual interaction. Use the GUI mode for real sessions.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| GUI doesn't appear | `xhost +local:docker` then `ec restart` |
| `/dev/net/tun` missing | `sudo modprobe tun` |
| DNS broken after disconnect | `ec stop` re-runs cleanup automatically |
| Container exits immediately | `ec logs` |
| No internet without VPN | Check `/etc/resolv.conf` — should have `1.1.1.1` and your router IP |
| Clipboard not filled | Check `CLIP_TEXT` in `.env`; ensure `xclip` is installed |
