#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# pack.sh — personalise openclaw/ using .env and copy result to jobs/
#
# Usage:
#   cp .env.example .env     # fill in your values
#   ./pack.sh                # generates jobs/ directory
#
# Then on the target machine:
#   cp -r jobs/. ~/.openclaw/
#   openclaw gateway start
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$REPO_DIR/.env"
SRC_DIR="$REPO_DIR/openclaw"
OUT_DIR="$REPO_DIR/jobs"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $*${NC}"; }
err()  { echo -e "${RED}  ✗ $*${NC}"; exit 1; }

echo ""
echo "📦 OpenClaw Pack Builder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Load .env ─────────────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  err ".env not found. Copy .env.example to .env and fill in your values."
fi

set -a; source "$ENV_FILE"; set +a

# Required fields
: "${AGENT_NAME:?AGENT_NAME is required in .env}"
: "${OWNER_NAME:?OWNER_NAME is required in .env}"

# Defaults
AGENT_EMOJI="${AGENT_EMOJI:-🤖}"
ORG_NAME="${ORG_NAME:-}"
OWNER_TIMEZONE="${OWNER_TIMEZONE:-UTC}"
MC_URL="${MC_URL:-https://mc.curatelearn.com}"
MC_AGENT_TOKEN="${MC_AGENT_TOKEN:-}"
MC_AGENT_ID="${MC_AGENT_ID:-main}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
GATEWAY_TOKEN="${GATEWAY_TOKEN:-$(python3 -c 'import secrets; print(secrets.token_hex(24))')}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_OWNER_ID="${TELEGRAM_OWNER_ID:-}"

echo "   Agent:  $AGENT_NAME $AGENT_EMOJI"
echo "   Owner:  $OWNER_NAME @ ${ORG_NAME:-no org}"
echo "   Output: $OUT_DIR"
echo ""

# ── Clean and recreate jobs/ ──────────────────────────────────────────────────
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# ── Template substitution function ───────────────────────────────────────────
inject_vars() {
  local file="$1"
  sed \
    -e "s|{{AGENT_NAME}}|$AGENT_NAME|g" \
    -e "s|{{AGENT_EMOJI}}|$AGENT_EMOJI|g" \
    -e "s|{{ORG_NAME}}|$ORG_NAME|g" \
    -e "s|{{OWNER_NAME}}|$OWNER_NAME|g" \
    -e "s|{{OWNER_TIMEZONE}}|$OWNER_TIMEZONE|g" \
    -e "s|{{MC_URL}}|$MC_URL|g" \
    -e "s|{{MC_AGENT_TOKEN}}|$MC_AGENT_TOKEN|g" \
    -e "s|{{MC_AGENT_ID}}|$MC_AGENT_ID|g" \
    -e "s|{{GATEWAY_PORT}}|$GATEWAY_PORT|g" \
    "$file"
}

# ── Copy and substitute workspace files ───────────────────────────────────────
echo "📁 Processing workspace files..."
mkdir -p "$OUT_DIR/workspace"
for f in "$SRC_DIR/workspace/"*; do
  fname=$(basename "$f")
  inject_vars "$f" > "$OUT_DIR/workspace/$fname"
  ok "$fname"
done

# ── Generate openclaw.json ────────────────────────────────────────────────────
echo ""
echo "⚙️  Generating openclaw.json..."

python3 - << PYEOF
import json, os

cfg = {
  "gateway": {
    "port": int("$GATEWAY_PORT"),
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    },
    "controlUi": {
      "allowedOrigins": [
        "http://localhost:$GATEWAY_PORT",
        "http://127.0.0.1:$GATEWAY_PORT"
      ],
      "allowInsecureAuth": True,
      "dangerouslyDisableDeviceAuth": True
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-6"
      },
      "workspace": os.path.expanduser("~/.openclaw/workspace"),
      "contextPruning": {"mode": "cache-ttl", "ttl": "1h"},
      "compaction": {"mode": "safeguard"},
      "heartbeat": {"every": "5h"},
      "maxConcurrent": 10
    },
    "list": [
      {"id": "main"}
    ]
  },
  "tools": {
    "web": {"search": {"enabled": True}, "fetch": {"enabled": True}},
    "exec": {"security": "full"}
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "bash": True,
    "restart": True
  },
  "cron": {"enabled": True},
  "web": {"enabled": True},
  "plugins": {
    "entries": {
      "telegram": {"enabled": True}
    }
  }
}

# Anthropic API key — goes in auth.profiles
if "$ANTHROPIC_API_KEY":
    cfg["auth"] = {
        "profiles": {
            "anthropic:default": {
                "provider": "anthropic",
                "mode": "api_key",
                "apiKey": "$ANTHROPIC_API_KEY"
            }
        },
        "order": {
            "anthropic": ["anthropic:default"]
        }
    }

# Telegram bot token — goes in channels.telegram.accounts
if "$TELEGRAM_BOT_TOKEN":
    account_cfg = {
        "botToken": "$TELEGRAM_BOT_TOKEN",
        "dmPolicy": "pairing",
        "groupPolicy": "allowlist",
        "streaming": "partial"
    }
    owner_id = "$TELEGRAM_OWNER_ID"
    cfg["channels"] = {
        "telegram": {
            "enabled": True,
            "dmPolicy": "pairing",
            "groupPolicy": "allowlist",
            "accounts": {
                "default": account_cfg
            }
        }
    }
    cfg["bindings"] = [
        {"agentId": "main", "match": {"channel": "telegram", "accountId": "default"}}
    ]
    # Allow elevated tools from owner if owner ID provided
    if owner_id:
        cfg["tools"]["elevated"] = {
            "enabled": True,
            "allowFrom": {"telegram": [int(owner_id)]}
        }

with open("$OUT_DIR/openclaw.json", "w") as f:
    json.dump(cfg, f, indent=2)

print("  \033[0;32m✓ openclaw.json\033[0m")
PYEOF

# ── Write install.sh into jobs/ ───────────────────────────────────────────────
echo ""
echo "📝 Writing install.sh..."
cat > "$OUT_DIR/install.sh" << 'INSTALL'
#!/usr/bin/env bash
# Run this on the target machine to install OpenClaw
set -euo pipefail

JOBS_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${HOME}/.openclaw"
OPENCLAW_VERSION="2026.3.28"

echo "🦞 Installing OpenClaw..."

# Install Node.js if missing
if ! command -v node &>/dev/null; then
  echo "  Node.js not found. Install from https://nodejs.org then re-run."
  exit 1
fi

# Install pinned openclaw version
if command -v openclaw &>/dev/null; then
  CURRENT=$(openclaw --version 2>/dev/null | awk '{print $2}' | head -1)
  if [ "$CURRENT" != "$OPENCLAW_VERSION" ]; then
    echo "  Updating openclaw to $OPENCLAW_VERSION..."
    npm install -g "openclaw@${OPENCLAW_VERSION}" --silent
  else
    echo "  ✓ openclaw $OPENCLAW_VERSION already installed"
  fi
else
  echo "  Installing openclaw $OPENCLAW_VERSION..."
  npm install -g "openclaw@${OPENCLAW_VERSION}" --silent
fi

# Wipe existing ~/.openclaw and start fresh
if [ -d "$TARGET" ]; then
  echo "  Removing existing ~/.openclaw..."
  rm -rf "$TARGET"
fi
mkdir -p "$TARGET"

# Copy workspace
if [ -d "$JOBS_DIR/workspace" ]; then
  cp -r "$JOBS_DIR/workspace" "$TARGET/workspace"
  echo "  ✓ workspace"
fi

# Copy openclaw.json
if [ -f "$JOBS_DIR/openclaw.json" ]; then
  cp "$JOBS_DIR/openclaw.json" "$TARGET/openclaw.json"
  echo "  ✓ openclaw.json"
fi

echo ""
echo "✅ Done! Start OpenClaw with:"
echo "   openclaw gateway start"
INSTALL
chmod +x "$OUT_DIR/install.sh"
ok "install.sh"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Pack ready in jobs/${NC}"
echo ""
echo "   jobs/"
echo "   ├── workspace/"
for f in "$OUT_DIR/workspace/"*; do echo "   │   └── $(basename "$f")"; done
echo "   ├── openclaw.json"
echo "   └── install.sh"
echo ""
echo "To deploy on a new machine:"
echo "  1. Copy the jobs/ folder to the new machine"
echo "  2. Run: chmod +x install.sh && ./install.sh"
echo "  3. Run: openclaw gateway start"
