<p align="center"><a href="https://pablomanjarres.com/oss/localhost-mirror"><img src=".github/banner.png" alt="Localhost Mirror" width="100%" /></a></p>

<h1 align="center">Localhost Mirror</h1>

<p align="center"><em>Like ngrok, but the URL only works on your own Tailscale devices.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/TypeScript%205.8-3178C6?style=flat&logo=typescript&logoColor=white" alt="TypeScript 5.8" />
  <img src="https://img.shields.io/badge/Swift%205.9-F05138?style=flat&logo=swift&logoColor=white" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/Node%2018%2B-5FA04E?style=flat&logo=node.js&logoColor=white" alt="Node 18+" />
  <img src="https://img.shields.io/badge/Express%205-000000?style=flat&logo=express&logoColor=white" alt="Express 5" />
  <img src="https://img.shields.io/badge/Tailscale-242424?style=flat&logo=tailscale&logoColor=white" alt="Tailscale" />
  <img src="https://img.shields.io/badge/macOS%2013%2B-000000?style=flat&logo=apple&logoColor=white" alt="macOS 13+" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-c8542a?style=flat" alt="License: MIT" />
  <img src="https://img.shields.io/badge/status-shipped-2ea44f?style=flat" alt="status: shipped" />
  <a href="https://pablomanjarres.com/portfolio/projects/localhost-mirror"><img src="https://img.shields.io/badge/Portfolio-write--up-c8542a?style=flat&logo=readme&logoColor=white" alt="Portfolio write-up" /></a>
  <a href="https://pablomanjarres.com/oss/localhost-mirror"><img src="https://img.shields.io/badge/Landing-pablo--oss-111111?style=flat&logo=vercel&logoColor=white" alt="Landing page" /></a>
</p>

Localhost Mirror exposes a port on your machine to your other devices, and only your other devices. It runs over Tailscale, so a tunnel opens from your phone, your tablet, or another Mac, and never from the public internet. Run `lm expose 3000` and you get a private URL the rest of your tailnet can visit. It ships as a terminal CLI and a native macOS menu-bar app that share one background daemon.

```console
$ lm expose 3000 --name myapp
  ✓ Exposing localhost:3000 → http://mac.tailnet.ts.net:19100/myapp

$ lm expose 5432 --token
  ✓ Exposing localhost:5432 → http://mac.tailnet.ts.net:19100/port-5432
    Token: x7Qk2p9_Fm3ZaR8tLbN0vW4y
    Full URL: http://mac.tailnet.ts.net:19100/port-5432?token=x7Qk2p9_Fm3ZaR8tLbN0vW4y

$ lm list

  NAME              LOCAL     URL                                       STATUS
  ────────────────────────────────────────────────────────────────────────────
  myapp             :3000     http://mac.tailnet.ts.net:19100/myapp     active
  port-5432         :5432     http://mac.tailnet.ts.net:19100/port-5432 active
```

## Why

Sharing a local dev server usually means a public tunnel that hands a URL to the whole internet, and often asks you to sign up for an account. Localhost Mirror keeps the one-command part and scopes access to devices you already own. You still get the open-it-on-your-phone workflow. You lose the part where anyone on the internet can reach your half-built app.

## Highlights

- **Tailnet-only by design.** Every request and every WebSocket upgrade is checked against the Tailscale CGNAT range (`100.64.0.0/10`) plus loopback before it reaches your local port. There is no public listener to find.
- **One port, many tunnels.** A single daemon on `:19100` fronts every tunnel. Visit `/<name>` or `?tunnel=<port>` and the daemon sets a cookie, then proxies you to the matching localhost port, WebSockets included.
- **Optional per-tunnel tokens.** `lm expose 3000 --token` mints a 24-character nanoid that the URL then requires as `?token=`. Without it, the request gets a 401.
- **A menu bar that knows your ports.** The macOS app scans listeners with `lsof`, labels them from 87 known ports and 28 process patterns (Next.js, Vite, Postgres, Ollama, and more), finds the owning project by walking up for `package.json`, `Cargo.toml`, `go.mod`, or `.git`, and exposes any of them in one click.
- **Health and resource watch.** The daemon HEAD-pings each target every 10 seconds to flip it between active and down, and the menu bar raises alerts for CPU over 80 percent, RAM over 500 MB, or zombie processes.
- **Self-managing daemon.** It auto-starts on your first `expose`, keeps atomic JSON state in `~/.localhost-mirror`, and shuts itself down 60 seconds after the last tunnel closes, unless you pass `--persistent`.

## How it works

Two front ends talk to one background daemon. The CLI and the menu-bar app both call a localhost-only management API on `:19099`. The daemon also runs the tailnet-facing server on `:19100`, where a raw HTTP server routes before Express: `/lm/*` serves the dashboard and its JSON API, `?tunnel=` and `/<name>` set the `lm_tunnel` cookie, and a present cookie proxies through `http-proxy` to the right localhost port.

```text
bin/lm.ts            CLI: expose · list · stop · status · dashboard · shutdown
src/daemon.ts        background service: management API + tailnet proxy/dashboard server
src/api.ts           tunnel CRUD, cookie + name routing, per-port proxy cache
src/auth.ts          localhost-only and tailnet-only access middleware
src/tailscale.ts     reads `tailscale status --json` for the IP and MagicDNS name
src/health.ts        10s HEAD-ping health checks
src/store.ts         atomic JSON state in ~/.localhost-mirror
src/dashboard/       single-file dark dashboard served at /lm/
app/Sources/…        SwiftUI menu-bar app: PortScanner · CommonPorts · DaemonClient
```

## CLI

| Command | What it does |
| --- | --- |
| `lm expose <port>` | Expose a local port. Flags: `--name <name>`, `--as <port>`, `--token`. |
| `lm list` (`ls`) | List active tunnels with their status. |
| `lm stop <target>` | Stop a tunnel by port, name, or `all`. |
| `lm status` | Show Tailscale and daemon status. |
| `lm dashboard` | Open the tunnel dashboard in your browser. |
| `lm shutdown` | Stop the daemon and every tunnel. |

## Tech stack

TypeScript 5.8 on Node 18+, with Express 5, `http-proxy`, Commander, chalk, and nanoid. The desktop app is SwiftUI on Swift 5.9, macOS 13+, built as a `MenuBarExtra`. Tailscale provides the network.

## Getting started

Prerequisites: Node 18+, and Tailscale installed and connected. No API keys, no accounts, no secrets.

```bash
npm install

# expose a port (the daemon auto-starts on first use)
npm run dev -- expose 3000 --name myapp

# or link the CLI and use `lm` directly
npm link
lm expose 3000 --name myapp --token
lm list
lm status
lm stop myapp
```

Install the macOS menu-bar app:

```bash
cd app
bash scripts/install.sh   # SwiftPM release build, then copy to /Applications
```

Every port and bind host is configurable, though none of it is required:

```bash
LM_MGMT_PORT=19099         # localhost-only management API port
LM_DASHBOARD_PORT=19100    # tailnet-facing proxy + dashboard port
LM_MGMT_HOST=127.0.0.1     # management API bind host
LM_DASHBOARD_HOST=0.0.0.0  # tunnel server bind host
```

## What's inside

**Node daemon and CLI (`bin/`, `src/`)**

| Path | Role |
| --- | --- |
| `bin/lm.ts` | The `lm` CLI. Auto-starts the daemon on first use, then talks to it over the management API. |
| `src/daemon.ts` | The background daemon: management API on `:19099`, tailnet server on `:19100`, health loop, and 60-second auto-shutdown. |
| `src/api.ts` | Tunnel create/list/delete, cookie and `/<name>` routing, the per-port `http-proxy` cache, and the 401/404/502 pages. |
| `src/proxy.ts` | A self-contained proxy factory with token checks (Bearer or `?token=`), a CIDR gate, and 401/403/502 responses. |
| `src/auth.ts` | Two middlewares: localhost-only for the management API, tailnet-only for the dashboard and tunnels. |
| `src/tailscale.ts` | Finds the Tailscale CLI and reads `tailscale status --json` for your IP and MagicDNS host. |
| `src/health.ts` | HEAD-pings every target on a 10-second interval and flips each tunnel between active and down. |
| `src/store.ts` | The JSON state file in `~/.localhost-mirror`, written atomically (temp file plus rename). |
| `src/dashboard/` | A single-file dark dashboard (`index.html`) served at `/lm/`. |
| `src/utils/` | Shared constants (ports, paths, intervals), the CGNAT check, and the chalk logger. |

**macOS menu-bar app (`app/`)**

| Path | Role |
| --- | --- |
| `app/Sources/LocalhostMirror/LocalhostMirrorApp.swift` | The `MenuBarExtra` entry point. |
| `PortScanner.swift` | The `lsof` scan, CPU/RAM/zombie stats, project detection, and the alert engine. |
| `CommonPorts.swift` | The 87-port and 28-pattern label and color table. |
| `DaemonClient.swift` | Talks to the daemon's management API on `:19099` and can start it. |
| `TunnelListView.swift` | The menu-bar window: ports, tunnels, alerts, and expose/stop/copy/kill actions. |
| `Models.swift` | Codable structs that mirror the daemon's JSON. |
| `app/scripts/` | `build.sh` (SwiftPM release build, ad-hoc sign) and `install.sh` (copy to `/Applications`). |

## License

MIT.

---

<p align="center">
  <a href="https://pablomanjarres.com/oss/localhost-mirror">Landing</a> ·
  <a href="https://pablomanjarres.com/portfolio/projects/localhost-mirror">Portfolio write-up</a> ·
  Built by Pablo Manjarres
</p>
