# ec commands

| Command       | What it does |
|---------------|--------------|
| `ec start`    | Start VPN (GUI). Auto-fills clipboard from `CLIP_TEXT`. |
| `ec cli`      | Start VPN headless using credentials from `.env`. |
| `ec stop`     | Stop VPN, flush iptables, delete `tun0`, restore DNS, flush resolved cache. |
| `ec status`   | Container state, VPN connection, keepalive PID. |
| `ec restart`  | Restart container. |
| `ec recreate` | Full stop + fresh start. Keeps credentials in `~/.easyconnect-data`. |
| `ec fix`      | Repair host network when VPN is stopped — flush iptables, delete `tun0`, restore DNS symlink, flush resolved cache, reapply active NM connection. Use when net is broken after crash / unclean exit. |
| `ec logs`     | Follow container logs. |
| `ec shell`    | Bash inside container. |
| `ec pull`     | Pull latest image. |
| `ec help`     | Print usage. |

## When to use what

- **Net broken, no VPN running** → `ec fix`
- **VPN frozen, want clean restart** → `ec stop` then `ec start`
- **Container in weird state** → `ec recreate`
- **Check if connected** → `ec status`
- **Debug connection issue** → `ec logs`
