# Localhost Mirror

> Like ngrok, except the tunnel never leaves your tailnet.

![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=flat&logo=typescript&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-F05138?style=flat&logo=swift&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-5FA04E?style=flat&logo=node.js&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-242424?style=flat&logo=tailscale&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?style=flat&logo=apple&logoColor=white)
![status](https://img.shields.io/badge/status-shipped-2ea44f?style=flat)
[![Portfolio](https://img.shields.io/badge/portfolio-pablomanjarres.com-c8542a?style=flat)](https://pablomanjarres.com/portfolio/projects/localhost-mirror)

Localhost Mirror exposes a port running on your machine to your other devices, and only your other devices. It rides on Tailscale, so a tunnel is reachable from your phone, tablet, or another Mac, but never from the public internet. Run `lm expose 3000` and you get a private URL the rest of your tailnet can open. It ships as a terminal CLI and a native macOS menu-bar app that share one background daemon.

## Why

Sharing a local dev server usually means a public tunnel that hands a URL to the whole internet and often wants an account. Localhost Mirror keeps the one-command convenience but scopes access to devices you already own. The QR-code-on-your-phone workflow stays; the "anyone can hit my half-built app" part goes away.

## Highlights

- **Tailnet-only by construction.** Every request and WebSocket upgrade is checked against the Tailscale CGNAT range (`100.64.0.0/10`) plus loopback before it touches your local port. There is no public listener to find.
- **One port, many tunnels.** A single daemon on `:19100` fronts everything. Visiting `/<name>` or `?tunnel=<port>` sets a cookie and the daemon proxies you to the right localhost port, WebSockets included.
- **Optional per-tunnel tokens.** `lm expose 3000 --token` mints a nanoid that the tunnel URL then requires as `?token=`. Without it, requests get a 401.
- **A menu bar that knows your ports.** The macOS app scans listeners with `lsof`, labels them from 87 known ports and 28 process heuristics (Next.js, Vite, Postgres, Ollama, and more), finds the owning project by walking up for `package.json` / `Cargo.toml` / `go.mod` / `.git`, and exposes any of them from the menu bar.
- **Health and resource watch.** Targets are HEAD-pinged every 10s to flip active/down, and the menu bar raises alerts for CPU over 80%, RAM over 500MB, or zombie processes.
- **Self-managing daemon.** Auto-starts on the first `expose`, keeps atomic JSON state in `~/.localhost-mirror`, and shuts itself down 60s after the last tunnel closes unless you pass `--persistent`.

## How it works

Two processes talk to one background daemon. The CLI and the menu-bar app both hit a localhost-only management API on `:19099`. The daemon also runs the tailnet-facing server on `:19100`, where a raw HTTP server routes before Express: `/lm/*` serves the dashboard and JSON API, `?tunnel=` and `/<name>` set the `lm_tunnel` cookie, and a present cookie proxies through `http-proxy` to that localhost port.

```
bin/lm.ts            CLI: expose · list · stop · status · dashboard · shutdown
src/daemon.ts        background service: mgmt API + tailnet proxy/dashboard server
src/api.ts           tunnel CRUD, cookie/name routing, per-port proxy cache
src/auth.ts          localhost-only + tailnet-only access middleware
src/tailscale.ts     reads `tailscale status --json` for IP + MagicDNS name
src/health.ts        10s HEAD-ping health checks
src/store.ts         atomic JSON state in ~/.localhost-mirror
src/dashboard/       single-file dark dashboard
app/Sources/…        SwiftUI menu-bar app: PortScanner · CommonPorts · DaemonClient
```

## Tech stack

TypeScript 5.8 on Node 18+, Express 5, `http-proxy`, Commander, chalk, and nanoid. The desktop app is SwiftUI on Swift 5.9, macOS 13+, built as a `MenuBarExtra`. Tailscale supplies the network.

## Getting started

Prerequisites: Node 18+, and Tailscale installed and connected. No API keys, no accounts, no secrets.

```bash
npm install

# expose a port — the daemon auto-starts on first use
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
bash scripts/install.sh   # builds with SwiftPM, installs to /Applications
```

Ports are configurable, though nothing here is required:

```bash
LM_MGMT_PORT=19099        # localhost-only management API
LM_DASHBOARD_PORT=19100   # tailnet-facing proxy + dashboard
```

---

Part of [Pablo Manjarres' portfolio](https://pablomanjarres.com/portfolio/projects/localhost-mirror).