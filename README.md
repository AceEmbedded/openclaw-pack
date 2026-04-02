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

```bash
# 1. Clone the repo
git clone https://github.com/AceEmbedded/openclaw-pack
cd openclaw-pack

# 2. Set up your env
cp .env.example .env
# Edit .env — fill in your name, API keys, tokens

# 3. Customise the agent (optional)
# Edit openclaw/workspace/SOUL.md, USER.md, AGENTS.md etc

# 4. Build
chmod +x pack.sh
./pack.sh

# 5. Deploy on any machine
# Copy jobs/ folder to the target machine, then:
chmod +x jobs/install.sh
./jobs/install.sh
openclaw gateway start
```

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
