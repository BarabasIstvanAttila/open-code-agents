---
name: homelab-deploy
description: Use when deploying or verifying Docker compose stacks on HomeLab hosts (pi3; nas/mac-studio later) from this Mac. Covers SSH deploy conventions, compose-file-per-stack layout, cwd/mount rules, git-drift gate, rollback pattern, and deterministic curl smoke verification. Pair with /mode build.
---

# HomeLab Deploy + Verify

Deploy = SSH from Mac. Verify = LAN curl from Mac. Deterministic checks only — every line is reproducible by hand.

## Host inventory

| Host | SSH | Repo path | Deploy dir | Notes |
|------|-----|-----------|------------|-------|
| pi3 | `pi@192.168.1.10` | `~/HomeLab` | `~/HomeLab/pi3` | keys installed via `ssh-copy-id`; LAN services |

## Compose-file-per-stack (pi3)

Runs from `~/HomeLab/pi3` ONLY — `./traefik` volume mounts are relative to cwd (mount-fix lesson 2026-07-26). `.env` exists on the target host only — never copy it.

| Stack | File | Services | Concern |
|-------|------|----------|---------|
| proxy | `compose/docker-compose.proxy.yml` | traefik, whoami, cloudflared | public/LAN edge |
| infra | `compose/docker-compose.infra.yml` | redis, authelia | backends |
| pihole | `compose/docker-compose.pihole.yml` | pihole | DNS |
| portainer | `compose/docker-compose.portainer.yml` | agent | mgmt |

External networks (`homelab-dmz`, `homelab-infrastructure`) are created once by `scripts/03-create-networks.sh` — compose files declare them `external: true`; never recreate from a stack.

## Git-drift gate (HARD -- run before every deploy)

Agents never run git mutations. Verify alignment instead:

```bash
# local vs remote HEAD
git -C /Users/atti/Projects/HomeLab rev-parse HEAD
ssh pi@192.168.1.10 'cd ~/HomeLab && git rev-parse HEAD'
```

Mismatch → STOP, show the user `git log --oneline <remote>..<local>` equivalent and wait for their decision (they commit/push, or explicitly accept deploying staged-but-unpush state — in which case warn that the deploy is NOT reproducible from git).

## Deploy procedure

```bash
# 1. syntax sanity (local, cheap)
cd /Users/atti/Projects/HomeLab/pi3 && docker compose -f compose/docker-compose.proxy.yml config --quiet

# 2. targeted deploy on pi3 (named services only — blanket `make deploy` risks dormant stacks)
ssh pi@192.168.1.10 'cd ~/HomeLab/pi3 && docker compose -f compose/docker-compose.proxy.yml up -d traefik whoami'

# 3. container state
ssh pi@192.168.1.10 'docker ps --filter name=pi3- --format "table {{.Names}}\t{{.Status}}"'

# 4. log scan (filter, never dump)
ssh pi@192.168.1.10 'docker logs pi3-traefik 2>&1 | tail -100 | grep -iE "error|fatal|panic" || echo LOGS_CLEAN'
```

## Smoke verification (tiered, deterministic)

```
container Up?  →  logs clean?  →  HTTP status+marker via Host header  →  DNS-based URL
```

Host-header curl checks routing WITHOUT depending on DNS; DNS-based curl validates the Pi-hole split-horizon path. Run the ready-made script and let exit code = failure count:

```bash
bash /Users/atti/Projects/HomeLab/pi3/scripts/smoke-traefik.sh              # full default table
bash /Users/atti/Projects/HomeLab/pi3/scripts/smoke-traefik.sh 192.168.1.10 # explicit IP
```

Manual patterns when no script exists for a stack:

```bash
curl -sf -o /dev/null -w '%{http_code}' --connect-timeout 5 -H 'Host: service.local.oagatar.uk' http://192.168.1.10/
curl -sf http://192.168.1.10:8080/api/http/routers | head -c 500   # traefik router inventory
```

Marker rule: status code alone is NOT enough for app backends — grep an expected body fragment (e.g. `Hostname:` for whoami) to prove the RIGHT backend answered, not a 404 fallback.

## Rollback pattern (HITL confirmation required)

```bash
ssh pi@192.168.1.10 'cd ~/HomeLab/pi3 && docker compose -f compose/docker-compose.proxy.yml down'
# config restore via git is the OPERATOR's action (commit ref from memory/tasks/ or git log)
```

## Report format (deploy-report.md)

```
# Deploy Report — <date>  /  target: pi3 (192.168.1.10)  /  ref: <branch @ SHA>
## Drift    local <SHA> vs remote <SHA> — aligned | gap: <n commits>
## Verdict  PASS | FAIL | PARTIAL
| Service | Container | Endpoint | Expected | Actual | Result |
```

## Deferred upgrade: Playwright MCP (browser verification)

Curl cannot prove SPA rendering (Traefik dashboard ships a JS shell). When visual/interactive checks become necessary, paste into `opencode.json` → `mcp`:

```json
"playwright": {
  "type": "local",
  "command": ["npx", "@playwright/mcp@latest", "--headless"],
  "enabled": true
}
```

plus `"playwright*": true` in the root `tools` map. One-time setup: `npx playwright install chromium`. Then agents can navigate, snapshot the accessibility tree, and screenshot into `.agent/verify/`. Keep smoke tests curl-based even then — MCP is for rendering proof, not regression gating.
