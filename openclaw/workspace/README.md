# Workspace Files — What to Edit

These are the files that define your AI agent's behaviour, identity, and context.
Edit them before running `pack.sh` from the repo root.

---

## 📄 SOUL.md — Agent Personality ⭐ Start here

**What it does:** Defines how the agent thinks, behaves, and communicates.

**What to change:**
- The agent's role and responsibilities
- Tone and communication style (formal vs casual, brief vs thorough)
- Any domain-specific rules (e.g. "always check Jira before creating tasks")
- Boundaries and things the agent should never do

**Placeholders used:** `{{AGENT_NAME}}`, `{{OWNER_NAME}}`, `{{ORG_NAME}}`

---

## 👤 USER.md — About Your Human

**What it does:** Gives the agent context about who they're working for.

**What to change:**
- Owner's name, role, timezone
- What they work on / their industry
- Communication preferences
- Any personal context the agent should know

**Placeholders used:** `{{OWNER_NAME}}`, `{{OWNER_TIMEZONE}}`, `{{ORG_NAME}}`

---

## 🏷️ IDENTITY.md — Agent Identity

**What it does:** Sets the agent's name, emoji, and org.

**What to change:**
- Nothing usually — all values come from `.env`
- Add a custom avatar URL if you have one

**Placeholders used:** `{{AGENT_NAME}}`, `{{AGENT_EMOJI}}`, `{{ORG_NAME}}`, `{{OWNER_NAME}}`

---

## 🤖 AGENTS.md — Workspace Behaviour

**What it does:** Instructions for how the agent manages its workspace —
how to handle memory, when to speak in group chats, heartbeat behaviour, etc.

**What to change:**
- Add custom conventions for your workflow
- Update group chat rules if you use Slack/Discord/Telegram groups
- Add specific tools or skills the agent should know about
- Change heartbeat check frequency or what to check

**Placeholders used:** None (edit freely)

---

## 📋 BOARD.md — Mission Control Task Board

**What it does:** Tells the agent how to interact with Mission Control (task board).

**What to change:**
- Only needed if you're using a custom Mission Control URL/token
- Otherwise leave as-is — `pack.sh` fills in values from `.env`

**Placeholders used:** `{{MC_URL}}`, `{{MC_AGENT_TOKEN}}`, `{{MC_AGENT_ID}}`

---

## 💓 HEARTBEAT.md — Periodic Tasks

**What it does:** A checklist the agent runs on every heartbeat (every ~30 min).

**What to change:**
- Add things you want the agent to check regularly
- Examples: check emails, review calendar, monitor a service, check GitHub PRs
- Keep it short — every item costs tokens

**Example:**
```markdown
- Check unread emails — flag anything urgent
- Check calendar for events in next 2 hours
- Check GitHub notifications
```

**Placeholders used:** None (edit freely)

---

## Quick Reference

| File | Priority | Edit? |
|------|----------|-------|
| `SOUL.md` | ⭐ High | Yes — defines who the agent is |
| `USER.md` | ⭐ High | Yes — who they're working for |
| `AGENTS.md` | Medium | Yes — workspace rules |
| `HEARTBEAT.md` | Medium | Yes — what to check periodically |
| `IDENTITY.md` | Low | Usually leave as-is |
| `BOARD.md` | Low | Leave as-is (auto-configured) |
