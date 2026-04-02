#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# openclaw-pack: inject.sh
# Installs an OpenClaw pack on a new machine.
# Fills in token placeholders, copies workspaces, and optionally starts the gateway.
#
# Usage:
#   ./inject.sh [options]
#
# Options:
#   --openclaw-dir DIR        Target directory (default: ~/.openclaw)
#   --provider-key KEY        LLM provider API key (Anthropic/OpenAI etc.)
#   --telegram-token TOKEN    Telegram bot token
#   --gateway-token TOKEN     Gateway auth token (auto-generated if not set)
#   --agent-token TOKEN       Mission Control agent token
#   --mc-url URL              Mission Control URL
#   --no-start                Don't start the gateway after install
#   --force                   Overwrite existing ~/.openclaw files
#   --env-file FILE           Load tokens from a .env file
#   --help                    Show this help
#
# Environment variables (alternative to flags):
#   OPENCLAW_PROVIDER_KEY, OPENCLAW_TELEGRAM_TOKEN, OPENCLAW_GATEWAY_TOKEN
#   OPENCLAW_AGENT_TOKEN, OPENCLAW_MC_URL
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
OPENCLAW_DIR="${HOME}/.openclaw"
PROVIDER_KEY="${OPENCLAW_PROVIDER_KEY:-}"
TELEGRAM_TOKEN="${OPENCLAW_TELEGRAM_TOKEN:-}"
GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
AGENT_TOKEN="${OPENCLAW_AGENT_TOKEN:-}"
MC_URL="${OPENCLAW_MC_URL:-https://mc.curatelearn.com}"
NO_START=false
FORCE=false
ENV_FILE=""
PACK_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
error()   { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --openclaw-dir)    OPENCLAW_DIR="$2"; shift 2 ;;
    --provider-key)    PROVIDER_KEY="$2"; shift 2 ;;
    --telegram-token)  TELEGRAM_TOKEN="$2"; shift 2 ;;
    --gateway-token)   GATEWAY_TOKEN="$2"; shift 2 ;;
    --agent-token)     AGENT_TOKEN="$2"; shift 2 ;;
    --mc-url)          MC_URL="$2"; shift 2 ;;
    --no-start)        NO_START=true; shift ;;
    --force)           FORCE=true; shift ;;
    --env-file)        ENV_FILE="$2"; shift 2 ;;
    --help|-h)
      grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
      exit 0 ;;
    *) error "Unknown argument: $1" ;;
  esac
done

# ── Load .env file if provided ────────────────────────────────────────────────
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  info "Loading env from $ENV_FILE"
  set -a; source "$ENV_FILE"; set +a
  PROVIDER_KEY="${OPENCLAW_PROVIDER_KEY:-$PROVIDER_KEY}"
  TELEGRAM_TOKEN="${OPENCLAW_TELEGRAM_TOKEN:-$TELEGRAM_TOKEN}"
  GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$GATEWAY_TOKEN}"
  AGENT_TOKEN="${OPENCLAW_AGENT_TOKEN:-$AGENT_TOKEN}"
  MC_URL="${OPENCLAW_MC_URL:-$MC_URL}"
fi

echo ""
echo "🦞 OpenClaw Pack Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Pack:   $PACK_DIR"
echo "   Target: $OPENCLAW_DIR"
echo ""

# ── Check manifest ────────────────────────────────────────────────────────────
if [ ! -f "$PACK_DIR/manifest.json" ]; then
  error "No manifest.json found. Are you running from inside the unzipped pack?"
fi

PACK_NAME=$(python3 -c "import json; print(json.load(open('$PACK_DIR/manifest.json'))['pack_name'])")
info "Installing pack: $PACK_NAME"

# ── Check openclaw is installed ───────────────────────────────────────────────
if ! command -v openclaw &>/dev/null; then
  warn "openclaw not found. Installing..."
  npm install -g openclaw 2>/dev/null || error "Failed to install openclaw. Install Node.js first: https://nodejs.org"
fi

OPENCLAW_VERSION=$(openclaw --version 2>/dev/null | head -1 || echo "unknown")
info "OpenClaw version: $OPENCLAW_VERSION"

# ── Interactive token collection ──────────────────────────────────────────────
echo ""
echo "🔑 Token Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━"

prompt_if_empty() {
  local var_name="$1"
  local prompt="$2"
  local default="$3"
  local secret="${4:-false}"
  local current="${!var_name:-}"

  if [ -z "$current" ]; then
    if [ "$secret" = "true" ]; then
      read -rsp "   $prompt${default:+ (press Enter to skip)}: " input
      echo ""
    else
      read -rp "   $prompt${default:+ [default: $default]}: " input
    fi
    if [ -n "$input" ]; then
      eval "$var_name=\"$input\""
    elif [ -n "$default" ]; then
      eval "$var_name=\"$default\""
    fi
  else
    echo -e "   ${GREEN}✓${NC} $prompt: ${current:0:8}..."
  fi
}

prompt_if_empty "PROVIDER_KEY"   "Anthropic/OpenAI API key" "" "true"
prompt_if_empty "TELEGRAM_TOKEN" "Telegram bot token (optional)" "" "true"

# Auto-generate gateway token if not provided
if [ -z "$GATEWAY_TOKEN" ]; then
  GATEWAY_TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(24))")
  info "Generated gateway token: ${GATEWAY_TOKEN:0:12}..."
fi

prompt_if_empty "AGENT_TOKEN"    "Mission Control agent token (optional)" "" "true"
prompt_if_empty "MC_URL"         "Mission Control URL" "https://mc.curatelearn.com" "false"

# ── Create target directory ───────────────────────────────────────────────────
echo ""
info "Setting up $OPENCLAW_DIR..."
mkdir -p "$OPENCLAW_DIR"

# ── Copy main workspace ───────────────────────────────────────────────────────
echo ""
echo "📁 Installing main workspace..."
ws_src="$PACK_DIR/workspace"
ws_dst="$OPENCLAW_DIR/workspace"
if [ -d "$ws_dst" ] && [ "$FORCE" != "true" ]; then
  warn "workspace already exists — skipping (use --force to overwrite)"
else
  cp -r "$ws_src" "$ws_dst"
  success "workspace (main agent)"
fi

# ── Install cron jobs ─────────────────────────────────────────────────────────
if [ -d "$PACK_DIR/cron" ]; then
  echo ""
  info "Installing cron jobs..."
  mkdir -p "$OPENCLAW_DIR/cron"
  cp -r "$PACK_DIR/cron/." "$OPENCLAW_DIR/cron/"
  success "Cron jobs installed"
fi

# ── Process openclaw.json template ───────────────────────────────────────────
if [ -f "$PACK_DIR/openclaw.json.template" ]; then
  echo ""
  info "Configuring openclaw.json..."

  EXISTING_CONFIG="$OPENCLAW_DIR/openclaw.json"
  TEMPLATE="$PACK_DIR/openclaw.json.template"

  python3 - << PYEOF
import json, sys, os

with open("$TEMPLATE") as f:
    cfg = json.load(f)

# Inject provider key
provider_key = "$PROVIDER_KEY"
if provider_key and "providers" in cfg:
    for pname, pval in cfg.get("providers", {}).items():
        if isinstance(pval, dict):
            for k in list(pval.keys()):
                if pval[k] == "__REPLACE_ME__" and "key" in k.lower():
                    cfg["providers"][pname][k] = provider_key

# Inject Telegram token
tg_token = "$TELEGRAM_TOKEN"
if tg_token:
    plugins = cfg.get("plugins", {}).get("entries", [])
    for p in plugins:
        if isinstance(p, dict) and "telegram" in str(p.get("id","")).lower():
            if isinstance(p.get("config"), dict):
                for k in p["config"]:
                    if p["config"][k] == "__REPLACE_ME__" and "token" in k.lower():
                        p["config"][k] = tg_token

# Inject gateway token
gw_token = "$GATEWAY_TOKEN"
if gw_token and "gateway" in cfg:
    if isinstance(cfg["gateway"].get("auth"), dict):
        if cfg["gateway"]["auth"].get("token") == "__REPLACE_ME__" or not cfg["gateway"]["auth"].get("token"):
            cfg["gateway"]["auth"]["token"] = gw_token

# Write result
out = "$EXISTING_CONFIG"
if os.path.exists(out):
    # Merge — don't overwrite existing good config
    with open(out) as f:
        existing = json.load(f)
    # Only inject into existing if values are placeholders
    def inject(existing, template, path=""):
        if isinstance(template, dict) and isinstance(existing, dict):
            for k, v in template.items():
                if k not in existing:
                    existing[k] = v
                else:
                    existing[k] = inject(existing[k], v, path+"."+k)
        elif isinstance(template, str) and template == "__REPLACE_ME__":
            return existing  # keep existing value
        return existing
    merged = inject(existing, cfg)
    with open(out, "w") as f:
        json.dump(merged, f, indent=2)
    print("   ✓ Merged into existing openclaw.json")
else:
    # Clean placeholders
    def clean(obj):
        if isinstance(obj, dict): return {k: clean(v) for k,v in obj.items()}
        if isinstance(obj, list): return [clean(i) for i in obj]
        if obj == "__REPLACE_ME__": return ""
        return obj
    with open(out, "w") as f:
        json.dump(clean(cfg), f, indent=2)
    print("   ✓ Created openclaw.json")
PYEOF

  # Update BOARD.md / TOOLS.md with MC config if tokens provided
  if [ -n "$AGENT_TOKEN" ]; then
    for ws in "$OPENCLAW_DIR"/workspace*/; do
      board="$ws/BOARD.md"
      tools="$ws/TOOLS.md"
      if [ -f "$board" ]; then
        sed -i "s|mc_.*|$AGENT_TOKEN|g" "$board" 2>/dev/null || true
      fi
      if [ -f "$tools" ]; then
        sed -i "s|mc_[a-f0-9]\{64\}|$AGENT_TOKEN|g" "$tools" 2>/dev/null || true
        sed -i "s|https://mc\.curatelearn\.com|$MC_URL|g" "$tools" 2>/dev/null || true
      fi
    done
    success "Agent token injected into workspace files"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "OpenClaw pack installed to $OPENCLAW_DIR"
echo ""
echo "   Provider key:    ${PROVIDER_KEY:+${PROVIDER_KEY:0:8}...}${PROVIDER_KEY:-not set}"
echo "   Telegram:        ${TELEGRAM_TOKEN:+configured}${TELEGRAM_TOKEN:-not set}"
echo "   Gateway token:   ${GATEWAY_TOKEN:0:12}..."
echo "   Agent token:     ${AGENT_TOKEN:+${AGENT_TOKEN:0:16}...}${AGENT_TOKEN:-not set}"
echo "   MC URL:          $MC_URL"
echo ""

# ── Start gateway ─────────────────────────────────────────────────────────────
if [ "$NO_START" != "true" ]; then
  echo "🚀 Starting OpenClaw gateway..."
  if openclaw gateway start --bind lan 2>/dev/null; then
    success "Gateway started"
    openclaw gateway status 2>/dev/null || true
  else
    warn "Could not start gateway automatically. Run: openclaw gateway start"
  fi
fi

echo ""
echo "🎉 Done! OpenClaw is ready."
echo ""
echo "Next steps:"
echo "  • Start gateway:    openclaw gateway start"
echo "  • Check status:     openclaw gateway status"
echo "  • View config:      openclaw config get gateway"
