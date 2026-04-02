# TEAM.md - Team Communication Guide

## The Team

| Agent | Name | Role | Telegram Bot | Handle |
|-------|------|------|-------------|--------|
| main | Falcon 🦅 | Team Lead | @falconPAbot | `@falconPAbot` |
| developer | James 💻 | Developer | @cl_developer_bot | `@cl_developer_bot` |
| marketer | Jenny 📣 | Marketer | @cl_marketer_bot | `@cl_marketer_bot` |
| pa | PA 🤝 | Personal Assistant | @Danny_pa_bot | `@Danny_pa_bot` |
| — | Daniel | Founder/Boss | — | Telegram ID: 7803638565 |

## CurateLearn Official Group
- **Chat ID:** -1003619866263
- **Channel:** telegram
- **Account for Falcon:** default
- This is the primary group for team updates, standups, and cross-agent conversation.

## How to Send a Message to the Group

Use the `message` tool:
```
action: send
channel: telegram
target: -1003619866263
message: "your message here"
```

## Tagging Rules — ALWAYS follow these

### When mentioning another agent in the group:
- Tag them by Telegram handle so they see it
- **Falcon:** `@falconPAbot`
- **James:** `@cl_developer_bot`
- **Jenny:** `@cl_marketer_bot`

### Examples:
- "Hey @cl_developer_bot — the landing page copy is ready, can you hook it up to the frontend?"
- "@cl_marketer_bot I've deployed the new feature, can you draft an announcement?"
- "@falconPAbot blocked on the API spec, need a decision before I can continue."
- "Tagging @cl_developer_bot and @cl_marketer_bot — standup time 🚀"

### When to post in the group:
- Daily standup (9am WAT) — every agent posts their own update
- When completing a task that affects another agent
- When blocked and need input from the team
- When you've been tagged by someone else — respond in the group
- Significant milestone or delivery

### When NOT to spam:
- Routine board updates (use task comments instead)
- Minor status changes (update the board, don't broadcast)
- Personal replies to Daniel (DM him directly)

## Cross-Agent Collaboration Flow
1. Get assigned a task
2. Do the work
3. If you need another agent → tag them in the group OR reassign the task on the board with a comment
4. When done → update task to "done" + post in group if it's significant
5. Always reference task IDs in group messages when relevant: "Task f90fd9d8 is done ✅"
