# EasyConnect Docker Setup

Runs Sangfor EasyConnect VPN client in Docker with X11 GUI forwarding.

## Requirements

- Docker + Docker Compose
- X11 display server
- TUN kernel module: `sudo modprobe tun`

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Container definition |
| `.env` | Environment config |
| `ec.sh` | Management script |

## Usage

```bash
ec start      # start VPN GUI
ec stop       # stop container
ec restart    # restart container
ec recreate   # full stop + fresh start (keeps saved credentials)
ec logs       # follow container logs
ec status     # show container status
ec shell      # bash inside container
ec pull       # pull latest image
```

> Add alias to shell: `alias ec="${HOME}/Docker/EasyConnect/ec.sh"`

## Data Persistence

Credentials and config saved to `~/.easyconnect-data` — survives container restarts and recreation.

## Key Design Decisions

**`EXIT=1`** — EasyConnect's internal startup script loops forever by default, restarting the GUI after every close. `EXIT=1` sets `MAX_RETRY=0`, so closing the window stops the container cleanly.

**`restart: "no"`** — Container does not auto-restart. Run `ec start` manually when you need the VPN.

**`--net=host`** — Required for VPN traffic to route through the host network stack.

## DNS

EasyConnect can break DNS by conflicting with `systemd-resolved`. Fixed by replacing the managed symlink with a static file:

```bash
sudo rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
```

**Tradeoff:** `systemd-resolved` is bypassed. DNS always hits Google/Cloudflare. VPN-pushed DNS (internal company hostnames) won't auto-apply. Fine for internet-only VPN use — breaks if you need to resolve internal hostnames over VPN.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| GUI doesn't appear | Run `xhost +local:docker` then `ec restart` |
| `/dev/net/tun` missing | `sudo modprobe tun` |
| Container exits immediately | Check `ec logs` |
| Old container with wrong restart policy | `ec recreate` |
