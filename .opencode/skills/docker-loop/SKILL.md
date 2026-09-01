---
name: docker-loop
description: Use when the orchestrator agent deploys and verifies containers ONE BY ONE on local Mac Docker (Docker Desktop / OrbStack) during a goal loop. Covers local network prelude, override + stub-env generation, single-service deploy, curl marker checks, and Playwright MCP browser verification with screenshots. Local loop only — SSH homelab deploys use the homelab-deploy skill instead.
---

# Docker Loop — Local Per-Container Deploy + Verify

Deploy = local Docker Desktop on this Mac. Verify = curl (status + marker) then Playwright browser (rendering proof). One container at a time, always.

## Environment facts (this Mac)

| Fact | Value |
|------|-------|
| Docker | Docker Desktop, context `desktop-linux`, active |
| JS runtime | `bun`/`bunx` at `/Users/atti/.bun/bin` — **NO node/npx installed**; every `npx …` in upstream docs becomes `bunx …` |
| Playwright browsers | `~/Library/Caches/ms-playwright/chromium-1234` (installed 2026-08-27) |
| Playwright MCP | `bunx @playwright/mcp@latest --headless` (server v1.63.x) — tools appear as `playwright_browser_navigate`, `playwright_browser_snapshot`, `playwright_browser_take_screenshot`, `playwright_browser_close` |
| Busy local ports | 9000 (Portainer), 3001 (Uptime Kuma), 3000 (Grafana), 8005 (oMLX), 4096 (opencode server) — **pick 18000–18999 for loop ports** |

## Port binding rule

All loop ports bind `127.0.0.1` ONLY (`"127.0.0.1:18080:80"`). Never `0.0.0.0` — this is a dev loop, not a service exposure.

## Pre-flight: image availability (this Mac has a daemon-proxy pull issue)

Docker Desktop routes pulls through `http.docker.internal:3128`; when the upstream host proxy app is down, pulls hang indefinitely while host curl still works (observed 2026-08-27). Before Strategy A:

```bash
docker image inspect <image> >/dev/null 2>&1 && echo IMAGE_LOCAL || echo IMAGE_MISSING
```

`IMAGE_MISSING` + a pull that makes no progress within ~60s → treat as **pull blocked**: record a finding, pivot to Strategy B with a locally available image, and surface the proxy issue to the operator in the report. Never sit through multi-minute silent pulls.

## YAML gotchas for generated compose files

- `command:` as **list form** (`["sh", "-c", "<script>"]` or `- sh` / `- -c` / `- <script>`) — never a plain scalar with `: ` inside (mapping-value parse error)
- Embedded scripts use a **single-quoted YAML scalar** with double quotes inside the script — YAML double-quoted scalars process `\n` into real newlines and break the embedded code

## Strategy A — repo compose + local override (preferred)

Base compose files reference external networks and `${VAR}` secrets that don't exist on the Mac. Fix with a prelude + override, never by editing the repo's compose or `.env` files.

### 1. Local network prelude (once per goal)

```bash
# pi3 compose files declare these as external: true — create them locally if missing
docker network create homelab-dmz 2>/dev/null
docker network create homelab-infrastructure 2>/dev/null
docker network create orchestrator-net 2>/dev/null || true
docker network ls --format '{{.Name}}'
```

### 2. Stub env (never touch real `.env`)

```bash
# extract every ${VAR} the base compose interpolates
grep -ohE '\$\{[A-Z_0-9]+' <base-compose> | sort -u | sed 's/\${//' \
  | while read v; do echo "$v=stub-$v"; done
```

Write the results to `.agent/orchestrator/.env.local` (throwaway stubs; compose hard-fails without values — stubs satisfy the gate for containers that don't really use them).

### 3. Override file (`.agent/orchestrator/override-N.yml`)

```yaml
# service-level networks REPLACE base networks; ports merge by target port
services:
  <service>:
    networks:
      - orchestrator-net
    ports:
      - "127.0.0.1:18080:80"
networks:
  orchestrator-net:
    name: orchestrator-net
```

Note: a service-level `networks:` in the override **replaces** the base networks for that service — that is what quarantines the container onto `orchestrator-net`. Top-level networks merge; the external `homelab-dmz` declaration in the base still resolves because of the prelude in step 1.

### 4. Single-service deploy

```bash
docker compose --env-file .agent/orchestrator/.env.local \
  -f <base-compose> -f .agent/orchestrator/override-N.yml \
  up -d <service>          # ONE named service — never bare `up -d`
```

## Strategy B — standalone local compose (fallback)

Use when the base compose cannot run locally: `cloudflared` (needs real tunnel token), host-specific bind mounts (`./traefik`, `/mnt/data`), or devices (`/dev/dri`). Generate `.agent/orchestrator/compose.local.yml` from scratch — same image, minimal env, `orchestrator-net`, `127.0.0.1` port — and record in findings-N.md that fidelity was reduced (image tested, base wiring not).

```yaml
services:
  <service>:
    image: <same-image-tag-as-base>
    container_name: orch-<service>
    networks: [orchestrator-net]
    ports: ["127.0.0.1:18080:<containerPort>"]
    environment:
      - KEY=stub-value
networks:
  orchestrator-net:
    name: orchestrator-net
```

## Verify — one container, five tiers, in order

```bash
# 1. config syntax
docker compose --env-file .agent/orchestrator/.env.local -f <base> -f <override> config --quiet && echo CONFIG_OK

# 2. container state
docker ps --filter name=<container> --format '{{.Names}} {{.Status}}'

# 3. log scan (filtered, never dumped)
docker logs <container> 2>&1 | grep -iE 'error|fatal|panic' || echo LOGS_CLEAN

# 4. curl: status + MARKER (status alone is NOT proof — grep a body fragment
#    to prove the RIGHT backend answered, not a 404 fallback)
curl -sf -o /tmp/body -w '%{http_code}' --connect-timeout 5 http://127.0.0.1:18080/
grep -q '<expected-marker>' /tmp/body && echo MARKER_OK
```

### 5. Browser proof (Playwright MCP)

For every container with a UI (and for any SPA where curl cannot prove rendering):

1. `playwright_browser_navigate` → `http://127.0.0.1:<port>`
2. `playwright_browser_snapshot` (accessibility tree) — assert the expected text/element is **rendered**, not just a JS shell
3. `playwright_browser_take_screenshot` → filename `.agent/orchestrator/verify/N-<service>.png`
4. `playwright_browser_close` between containers (fresh page per verification)

Assertion rule: title alone is weak; assert a visible text fragment from the snapshot. For APIs (no UI), curl tier 4 is sufficient — record "no-UI: curl-tier" in findings.

## Artifacts layout

```
.agent/orchestrator/
├── goal.md           # PHASE 0, immutable during iterations
├── plan-N.md         # per-iteration plan (container order, edits, expected outcomes)
├── findings-N.md     # verdict table + deviations vs plan + TODOs for next iteration
├── override-N.yml    # local override (Strategy A) or compose.local.yml (Strategy B)
├── .env.local        # throwaway stubs — NEVER the repo's real .env
├── verify/N-*.png    # browser screenshots
└── report.md         # final report (goal, iterations, verdicts, teardown command)
```

## Anti-patterns (HARD STOPS)

- Bare `up -d` / `down` without named services
- Editing or copying the repo's real `.env` / `.env.example` files
- Ports bound to `0.0.0.0`
- PASS without a marker (curl) or rendered-text assertion (browser)
- `rm` of any kind
- SSH to homelab hosts — local loop only (homelab-deploy skill owns SSH)
- Tearing down containers the loop didn't create

## Teardown (end of goal — printed for the operator, never auto-run)

```bash
docker compose --env-file .agent/orchestrator/.env.local -f <base> -f <override> down <services>
docker network rm orchestrator-net   # only if no other loop container uses it
```
