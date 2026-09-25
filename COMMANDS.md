# ec commands

| Command       | What it does |
|---------------|--------------|
| `ec up`       | Start VPN (GUI). Auto-fills clipboard from `CLIP_TEXT`. |
| `ec cli`      | Start VPN headless using credentials from `.env`. |
| `ec down`     | Stop VPN, flush iptables, delete `tun0`, restore DNS, flush resolved cache. |
| `ec toggle`   | `ec up` if stopped, `ec down` if running. Used by the app launcher and quick-settings toggle. |
| `ec status`   | Container state, VPN connection, keepalive PID. |
| `ec restart`  | Restart container. |
| `ec recreate` | Full down + fresh up. Keeps credentials in `~/.easyconnect-data`. |
| `ec fix`      | Repair host network when VPN is stopped — flush iptables, delete `tun0`, restore DNS symlink, flush resolved cache, reapply active NM connection. Use when net is broken after crash / unclean exit. |
| `ec logs`     | Follow container logs. |
| `ec shell`    | Bash inside container. |
| `ec pull`     | Pull latest image. |
| `ec help`     | Print usage. |

## When to use what

- **Net broken, no VPN running** → `ec fix`
- **VPN frozen, want clean restart** → `ec down` then `ec up`
- **Container in weird state** → `ec recreate`
- **Check if connected** → `ec status`
- **Debug connection issue** → `ec logs`
