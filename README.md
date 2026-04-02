# openclaw-pack

**Portable OpenClaw agent provisioner** — generate a zip from any OpenClaw machine and deploy it on a new machine with one command.

## How it works

```
[Old Machine]                         [New Machine]
  ./generate-pack.sh                    unzip openclaw-pack-*.zip
       │                                cd openclaw-pack-*/
       ▼                                ./inject.sh
  openclaw-pack-20260402.zip  ───────►  ~/.openclaw/ ready to go
```

## Generate a pack

On the machine with a working OpenClaw setup:

```bash
git clone https://github.com/AceEmbedded/openclaw-pack
cd openclaw-pack
chmod +x generate-pack.sh inject.sh
./generate-pack.sh --name my-agent
```

Output: `my-agent-pack-20260402-120000.zip`

## Deploy on a new machine

```bash
# Install Node.js first if needed: https://nodejs.org

# Unzip and run
unzip my-agent-pack-*.zip
cd my-agent-pack-*/
chmod +x inject.sh
./inject.sh
```

The installer will prompt for any tokens it needs.

## Non-interactive deployment (CI/automation)

Pass tokens as environment variables or flags:

```bash
OPENCLAW_PROVIDER_KEY="sk-ant-..." \
OPENCLAW_TELEGRAM_TOKEN="123456:ABC..." \
OPENCLAW_AGENT_TOKEN="mc_abc123..." \
OPENCLAW_MC_URL="https://mc.yourcompany.com" \
./inject.sh --no-start
```

Or use a `.env` file:

```bash
./inject.sh --env-file /path/to/.env
```

## What's in a pack

| File | Description |
|------|-------------|
| `workspace/` | Falcon's workspace (SOUL.md, MEMORY.md, etc.) |
| `workspace-developer/` | James's workspace |
| `workspace-marketer/` | Jenny's workspace |
| `openclaw.json.template` | Config with secrets redacted as `__REPLACE_ME__` |
| `cron/` | Scheduled jobs (if any) |
| `inject.sh` | Installer script |
| `manifest.json` | Pack metadata |

Secrets (API keys, tokens) are **never included** in the zip — inject.sh prompts for them at install time.

## inject.sh options

```
--openclaw-dir DIR       Target directory (default: ~/.openclaw)
--provider-key KEY       LLM API key (Anthropic/OpenAI etc.)
--telegram-token TOKEN   Telegram bot token
--gateway-token TOKEN    Gateway auth token (auto-generated if omitted)
--agent-token TOKEN      Mission Control agent token
--mc-url URL             Mission Control URL
--env-file FILE          Load tokens from .env file
--no-start               Don't auto-start the gateway
--force                  Overwrite existing files
```

## generate-pack.sh options

```
--output DIR    Output directory for the zip (default: current dir)
--name NAME     Pack name prefix (default: openclaw)
```
