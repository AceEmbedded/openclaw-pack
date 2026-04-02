#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# setup.sh — Set up OpenClaw on a brand new machine
#
# Usage:
#   ./setup.sh ./jobs          # from local jobs/ folder
#   ./setup.sh /path/to/jobs   # from any path
#
# What it does:
#   1. Installs Node.js (if missing)
#   2. Installs OpenClaw CLI (if missing)
#   3. Copies workspace files to ~/.openclaw/workspace/
#   4. Copies openclaw.json to ~/.openclaw/
#   5. Starts the OpenClaw gateway
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()    { echo -e "${GREEN}  ✓ $*${NC}"; }
info()  { echo -e "${BLUE}  → $*${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠ $*${NC}"; }
err()   { echo -e "${RED}  ✗ $*${NC}"; exit 1; }
step()  { echo -e "\n${BOLD}$*${NC}"; }

# ── Args ──────────────────────────────────────────────────────────────────────
JOBS_DIR="${1:-}"

if [ -z "$JOBS_DIR" ]; then
  err "Usage: ./setup.sh <path-to-jobs-folder>
  
  Example:
    ./setup.sh ./jobs
    ./setup.sh /tmp/openclaw-jobs"
fi

JOBS_DIR="$(cd "$JOBS_DIR" && pwd)"

if [ ! -d "$JOBS_DIR" ]; then
  err "Jobs folder not found: $JOBS_DIR"
fi

if [ ! -f "$JOBS_DIR/openclaw.json" ]; then
  err "No openclaw.json found in $JOBS_DIR. Run pack.sh first."
fi

OPENCLAW_DIR="${HOME}/.openclaw"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}🦞 OpenClaw Setup${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Jobs:   $JOBS_DIR"
echo "  Target: $OPENCLAW_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Node.js ───────────────────────────────────────────────────────────
step "1. Checking Node.js..."

if command -v node &>/dev/null; then
  NODE_VER=$(node --version)
  ok "Node.js $NODE_VER already installed"
else
  info "Installing Node.js 22..."
  
  if command -v apt-get &>/dev/null; then
    # Debian/Ubuntu
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
    apt-get install -y nodejs > /dev/null 2>&1
  elif command -v brew &>/dev/null; then
    # macOS
    brew install node@22 > /dev/null 2>&1
  elif command -v yum &>/dev/null; then
    # RHEL/CentOS
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
    yum install -y nodejs > /dev/null 2>&1
  else
    err "Cannot install Node.js automatically. Install manually from https://nodejs.org then re-run."
  fi
  
  ok "Node.js $(node --version) installed"
fi

# ── Step 2: OpenClaw CLI ──────────────────────────────────────────────────────
step "2. Checking OpenClaw..."

OPENCLAW_VERSION="2026.3.28"

if command -v openclaw &>/dev/null; then
  OC_VER=$(openclaw --version 2>/dev/null | head -1 | awk '{print $2}' || echo "installed")
  ok "OpenClaw $OC_VER already installed"
  if [ "$OC_VER" != "$OPENCLAW_VERSION" ]; then
    warn "Version mismatch (have $OC_VER, pack built with $OPENCLAW_VERSION) — reinstalling pinned version..."
    npm install -g "openclaw@${OPENCLAW_VERSION}" > /dev/null 2>&1
    ok "OpenClaw $OPENCLAW_VERSION installed"
  fi
else
  info "Installing OpenClaw $OPENCLAW_VERSION..."
  npm install -g "openclaw@${OPENCLAW_VERSION}" > /dev/null 2>&1
  ok "OpenClaw $OPENCLAW_VERSION installed"
fi

# ── Step 3: Wipe and recreate ~/.openclaw ─────────────────────────────────────
step "3. Setting up ~/.openclaw..."

if [ -d "$OPENCLAW_DIR" ]; then
  warn "Removing existing ~/.openclaw..."
  rm -rf "$OPENCLAW_DIR"
fi
mkdir -p "$OPENCLAW_DIR"
ok "Directory ready: $OPENCLAW_DIR"

# ── Step 4: Copy workspace ────────────────────────────────────────────────────
step "4. Installing workspace..."

if [ -d "$JOBS_DIR/workspace" ]; then
  cp -r "$JOBS_DIR/workspace" "$OPENCLAW_DIR/workspace"
  ok "Workspace installed"
  
  # List installed files
  for f in "$OPENCLAW_DIR/workspace/"*.md; do
    echo "     $(basename "$f")"
  done
else
  warn "No workspace folder found in jobs — skipping"
fi

# ── Step 5: Install openclaw.json ─────────────────────────────────────────────
step "5. Installing config..."

cp "$JOBS_DIR/openclaw.json" "$OPENCLAW_DIR/openclaw.json"
ok "openclaw.json installed"

# Show what was configured (without secrets)
python3 - << PYEOF
import json
with open("$OPENCLAW_DIR/openclaw.json") as f:
    cfg = json.load(f)

gw = cfg.get("gateway", {})
print(f"     Gateway port:  {gw.get('port', 18789)}")
print(f"     Gateway bind:  {gw.get('bind', 'loopback')}")
print(f"     Auth mode:     {gw.get('auth', {}).get('mode', 'none')}")

agents = cfg.get("agents", {}).get("list", [])
if agents:
    print(f"     Agents:        {', '.join(a.get('name', a.get('id','?')) for a in agents)}")

providers = list(cfg.get("providers", {}).keys())
if providers:
    print(f"     Providers:     {', '.join(providers)}")

plugins = cfg.get("plugins", {}).get("entries", [])
enabled = [p.get("id","?") for p in plugins if p.get("enabled")]
if enabled:
    print(f"     Plugins:       {', '.join(enabled)}")
PYEOF

# ── Step 6: Start gateway ─────────────────────────────────────────────────────
step "6. Starting OpenClaw gateway..."

# Stop any existing gateway first
openclaw gateway stop 2>/dev/null || true
sleep 1

if openclaw gateway start 2>/dev/null; then
  sleep 2
  STATUS=$(openclaw gateway status 2>/dev/null | head -3 || echo "")
  ok "Gateway started"
  if [ -n "$STATUS" ]; then
    echo "$STATUS" | sed 's/^/     /'
  fi
else
  warn "Could not auto-start gateway. Start manually with: openclaw gateway start"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}${BOLD}✅ OpenClaw is ready!${NC}"
echo ""

GW_PORT=$(python3 -c "import json; print(json.load(open('$OPENCLAW_DIR/openclaw.json')).get('gateway',{}).get('port',18789))" 2>/dev/null || echo "18789")
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "your-ip")

echo "  Access the dashboard:"
echo -e "    Local:   ${BLUE}http://localhost:$GW_PORT${NC}"
echo -e "    Network: ${BLUE}http://$HOST_IP:$GW_PORT${NC}"
echo ""
echo "  Useful commands:"
echo "    openclaw gateway status"
echo "    openclaw gateway stop"
echo "    openclaw gateway restart"
echo ""
