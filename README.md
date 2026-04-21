# docker-easyconnect

Sangfor EasyConnect VPN in Docker with X11 GUI, persistent credentials, and automatic iptables cleanup on disconnect.

## Requirements

- Docker + Docker Compose
- X11 display server
- `sudo modprobe tun` if `/dev/net/tun` is missing

## Setup

```bash
git clone https://github.com/dhoridho/docker-easyconnect
cd docker-easyconnect
bash setup.sh
source ~/.bashrc
```

First launch: enter your company VPN URL, connect, close the window. Credentials save to `~/.easyconnect-data` on exit.

## Usage

```bash
ec start      # start VPN
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

**iptables cleanup on disconnect** — EasyConnect adds iptables rules on connect that survive container stop. `ec stop` (and the background watcher on window close) flushes all rules and reloads UFW automatically.

**DNS** — `systemd-resolved` conflicts with EasyConnect. `setup.sh` replaces `/etc/resolv.conf` with a static file using `1.1.1.1` + your router gateway. Avoid `8.8.8.8` — EasyConnect routes it through `tun0`, breaking DNS when VPN is down. On disconnect, DNS is re-detected from the current network's default route.

**Credentials** — saved to `~/.easyconnect-data` which maps to `/root/conf` inside the container (not `/root/.easyconnect` — common mistake).

**Image** — pinned to a specific digest. To upgrade, pull a new image, update `IMAGE` in `.env`, run `ec recreate`.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| GUI doesn't appear | `xhost +local:docker` then `ec restart` |
| `/dev/net/tun` missing | `sudo modprobe tun` |
| DNS broken after disconnect | `ec stop` re-runs cleanup; or run `ec stop` manually |
| Container exits immediately | `ec logs` |
| No internet without VPN | Check `/etc/resolv.conf` — should have `1.1.1.1` and your router IP |
