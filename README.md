# openclaw-pack

Portable OpenClaw setup. Edit the files, fill in your `.env`, run `pack.sh` — get a ready-to-deploy `jobs/` folder.

## How it works

```
openclaw-pack/
├── openclaw/workspace/    ← edit these (SOUL.md, AGENTS.md etc)
├── .env.example           ← copy to .env, fill in tokens
├── pack.sh                ← builds jobs/ from openclaw/ + .env
└── jobs/                  ← generated output (gitignored), copy to ~/.openclaw
```

## Quick Start

### On your machine (build the pack)

```bash
# 1. Clone the repo
git clone https://github.com/AceEmbedded/openclaw-pack
cd openclaw-pack

# 2. Fill in your tokens
cp .env.example .env
nano .env   # add API key, Telegram token, etc.

# 3. Customise your agent (optional)
# See openclaw/workspace/README.md for what to edit
nano openclaw/workspace/SOUL.md
nano openclaw/workspace/USER.md

# 4. Build — generates jobs/ folder
chmod +x pack.sh
./pack.sh
```

### On any new machine (deploy)

```bash
# Copy jobs/ folder to the new machine, then run:
chmod +x setup.sh
./setup.sh ./jobs
```

That's it. `setup.sh` installs Node.js + OpenClaw, copies config and workspace, and starts the gateway.

## .env variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AGENT_NAME` | ✅ | Name of the AI agent |
| `AGENT_EMOJI` | | Agent emoji (default: 🤖) |
| `ORG_NAME` | | Organisation name |
| `OWNER_NAME` | ✅ | Your name |
| `OWNER_TIMEZONE` | | Your timezone (default: UTC) |
| `ANTHROPIC_API_KEY` | | Anthropic API key |
| `TELEGRAM_BOT_TOKEN` | | Telegram bot token |
| `TELEGRAM_OWNER_ID` | | Your Telegram user ID |
| `MC_URL` | | Mission Control URL |
| `MC_AGENT_TOKEN` | | Mission Control agent token |
| `GATEWAY_PORT` | | Gateway port (default: 18789) |
| `GATEWAY_TOKEN` | | Gateway auth token (auto-generated if blank) |

## Customising the agent

Edit files in `openclaw/workspace/` before running `pack.sh`:

- **SOUL.md** — agent personality and behaviour
- **USER.md** — context about the owner
- **IDENTITY.md** — agent name, emoji, org
- **AGENTS.md** — how the agent should behave
- **BOARD.md** — Mission Control task board config
- **HEARTBEAT.md** — periodic tasks to check

Use `{{PLACEHOLDER}}` syntax — `pack.sh` replaces them from `.env`.

## jobs/ folder

`pack.sh` generates `jobs/` (gitignored) containing:
- `workspace/` — personalised workspace files ready for `~/.openclaw/workspace/`
- `openclaw.json` — fully configured gateway + providers
- `install.sh` — one-command installer for the target machine
