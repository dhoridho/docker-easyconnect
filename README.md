# docker-easyconnect

Sangfor EasyConnect VPN in Docker with X11 GUI, persistent credentials, automatic clipboard fill, and iptables cleanup on disconnect.

## Compatibility

Tested on **Ubuntu 24.04 with GNOME**. Should work on any Ubuntu/Debian with an X11 display. Other distros (Arch, Fedora) may need manual adjustments — `apt-get`, `ufw`, and `libnotify` are Ubuntu/Debian-specific.

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

| Command       | What it does |
|---------------|--------------|
| `ec start`    | Start VPN (GUI) |
| `ec cli`      | Start VPN headless using credentials from `.env` |
| `ec stop`     | Stop VPN, flush iptables, delete `tun0`, restore DNS |
| `ec status`   | Container + VPN connection state + keepalive PID |
| `ec restart`  | Restart container |
| `ec recreate` | Full stop + fresh start (keeps credentials) |
| `ec fix`      | Repair host network when VPN is stopped — flush iptables, delete `tun0`, restore DNS symlink, flush resolved cache, reapply active NetworkManager connection. Use when net is broken after a crash or unclean exit. |
| `ec logs`     | Follow container logs |
| `ec shell`    | Bash inside container |
| `ec pull`     | Pull latest image |

`ec` is installed to `/usr/local/bin` — works from anywhere, no shell alias needed.

## How it works

**GUI close stops the container** — `EXIT=1` breaks EasyConnect's internal restart loop. Closing the window exits cleanly instead of looping forever.

**Clipboard auto-fill** — if `CLIP_TEXT` is set in `.env`, `ec start` copies it to the host clipboard automatically. Paste into the VPN password field on first connection.

**iptables cleanup on disconnect** — EasyConnect adds iptables rules on connect that survive container stop. `ec stop` (and the background watcher on window close) flushes all rules and reloads UFW automatically. Also deletes `tun0` if still up.

**DNS** — EasyConnect's own `ECAgent` hooks `systemd-resolved` directly once connected (confirmed via `need_hook_dns_server.ini` in its data dir), so `ec.sh` does not set DNS on connect — a prior version did (`resolvectl` + a hardcoded `8.8.8.8`) and it raced against ECAgent's own writes, which was the actual cause of intermittent DNS breakage. `setup.sh` only ensures `/etc/resolv.conf` starts as a symlink to `/run/systemd/resolve/resolv.conf` (systemd-resolved's normal uplink file) so ECAgent has a clean target to hook. On disconnect/stop/fix, `_cleanup_iptables` restores that symlink and flushes the resolved cache.

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
