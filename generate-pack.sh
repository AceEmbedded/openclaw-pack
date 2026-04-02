#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# openclaw-pack: generate-pack.sh
# Creates a portable OpenClaw pack from the current machine's ~/.openclaw
#
# Usage:
#   ./generate-pack.sh [--output ./my-pack.zip] [--name my-agent]
#
# Output: openclaw-pack-<name>-<date>.zip
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
OUTPUT_DIR="."
PACK_NAME="openclaw"
while [[ $# -gt 0 ]]; do
  case $1 in
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --name)   PACK_NAME="$2";  shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
DATE=$(date +%Y%m%d-%H%M%S)
PACK_FILE="${OUTPUT_DIR}/${PACK_NAME}-pack-${DATE}.zip"
TMP_DIR=$(mktemp -d)
STAGING="${TMP_DIR}/openclaw-pack"
mkdir -p "$STAGING"

echo "🦞 OpenClaw Pack Generator"
echo "   Source:  $OPENCLAW_DIR"
echo "   Output:  $PACK_FILE"
echo ""

# ── Copy workspaces ───────────────────────────────────────────────────────────
echo "📁 Copying workspaces..."
for ws in workspace workspace-developer workspace-marketer workspace-pa; do
  if [ -d "$OPENCLAW_DIR/$ws" ]; then
    cp -r "$OPENCLAW_DIR/$ws" "$STAGING/$ws"
    echo "   ✓ $ws"
  fi
done

# Also copy any custom workspace-* directories
for ws in "$OPENCLAW_DIR"/workspace-*; do
  name=$(basename "$ws")
  if [ ! -d "$STAGING/$name" ] && [ -d "$ws" ]; then
    cp -r "$ws" "$STAGING/$name"
    echo "   ✓ $name (custom)"
  fi
done

# ── Copy config (sanitized) ───────────────────────────────────────────────────
echo ""
echo "⚙️  Processing openclaw.json..."
if [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
  # Replace sensitive values with placeholders
  python3 - << PYEOF
import json, sys

with open("$OPENCLAW_DIR/openclaw.json") as f:
    cfg = json.load(f)

def sanitize(obj, path=""):
    if isinstance(obj, dict):
        result = {}
        for k, v in obj.items():
            full = path + "." + k if path else k
            result[k] = sanitize(v, full)
        return result
    elif isinstance(obj, str):
        # Redact known secret fields
        secret_keys = ["token", "password", "secret", "key", "apiKey", "api_key",
                       "accessToken", "access_token", "bot_token", "botToken"]
        p_lower = path.lower()
        if any(s in p_lower for s in secret_keys) and len(obj) > 8:
            return "__REPLACE_ME__"
        return obj
    elif isinstance(obj, list):
        return [sanitize(i, path) for i in obj]
    return obj

sanitized = sanitize(cfg)

# Also reset machine-specific network settings
if "gateway" in sanitized:
    if "remote" in sanitized["gateway"]:
        sanitized["gateway"]["remote"] = {"url": "__REPLACE_ME__"}
    if "controlUi" in sanitized["gateway"]:
        sanitized["gateway"]["controlUi"]["allowedOrigins"] = [
            "http://localhost:18789",
            "http://127.0.0.1:18789"
        ]

with open("$STAGING/openclaw.json.template", "w") as f:
    json.dump(sanitized, f, indent=2)

print("   ✓ openclaw.json.template (secrets redacted)")
PYEOF
fi

# ── Copy cron jobs (optional) ─────────────────────────────────────────────────
if [ -d "$OPENCLAW_DIR/cron" ]; then
  cp -r "$OPENCLAW_DIR/cron" "$STAGING/cron"
  echo "   ✓ cron jobs"
fi

# ── Write inject.sh into pack ─────────────────────────────────────────────────
echo ""
echo "📝 Writing inject.sh..."
cp "$(dirname "$0")/inject.sh" "$STAGING/inject.sh" 2>/dev/null || \
  curl -sSL "https://raw.githubusercontent.com/AceEmbedded/openclaw-pack/main/inject.sh" -o "$STAGING/inject.sh" 2>/dev/null || \
  echo "⚠️  inject.sh not found — download from https://github.com/AceEmbedded/openclaw-pack"
chmod +x "$STAGING/inject.sh" 2>/dev/null || true

# ── Write manifest ────────────────────────────────────────────────────────────
python3 - << PYEOF
import json, os, datetime

manifest = {
    "generated_at": datetime.datetime.utcnow().isoformat() + "Z",
    "pack_name": "$PACK_NAME",
    "source_host": os.uname().nodename,
    "workspaces": [d for d in os.listdir("$STAGING") if os.path.isdir(os.path.join("$STAGING", d)) and d.startswith("workspace")],
    "has_cron": os.path.isdir("$STAGING/cron"),
    "has_config_template": os.path.exists("$STAGING/openclaw.json.template"),
    "instructions": "Run inject.sh to install on a new machine",
}

with open("$STAGING/manifest.json", "w") as f:
    json.dump(manifest, f, indent=2)
print("   ✓ manifest.json")
PYEOF

# ── Write README ──────────────────────────────────────────────────────────────
cat > "$STAGING/README.md" << 'README'
# OpenClaw Pack

Portable OpenClaw agent setup. Run `inject.sh` on the target machine to install.

## Quick Install

```bash
unzip openclaw-pack-*.zip
cd openclaw-pack-*/
chmod +x inject.sh
./inject.sh
```

## What's included

- Agent workspaces (SOUL.md, MEMORY.md, TOOLS.md, etc.)
- `openclaw.json.template` — config with placeholders for secrets
- `inject.sh` — interactive installer that fills in your tokens
- `cron/` — scheduled jobs (if any)

## Tokens you'll need

- OpenClaw provider API key (Anthropic, OpenAI, etc.)
- Telegram bot token (if using Telegram)
- Any other channel tokens

Run `inject.sh --help` for all options.
README

echo "   ✓ README.md"

# ── Zip it up ─────────────────────────────────────────────────────────────────
echo ""
echo "📦 Creating zip..."
mkdir -p "$OUTPUT_DIR"
cd "$TMP_DIR"
zip -r "$PACK_FILE" "openclaw-pack/" -x "*/node_modules/*" -x "*/.git/*" -x "*/sessions/*" -x "*/logs/*" -q
echo "   ✓ $(du -sh "$PACK_FILE" | cut -f1) — $PACK_FILE"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$TMP_DIR"

echo ""
echo "✅ Pack ready: $PACK_FILE"
echo ""
echo "To deploy on another machine:"
echo "  1. Copy $PACK_FILE to target machine"
echo "  2. unzip $(basename "$PACK_FILE")"
echo "  3. cd openclaw-pack-*/"
echo "  4. ./inject.sh"
