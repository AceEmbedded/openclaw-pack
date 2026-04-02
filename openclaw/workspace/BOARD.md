# BOARD.md - Mission Control Task Board

Your task board lives at: **{{MC_URL}}** (prod) or **http://127.0.0.1:3333** (local)

## Agent Auth
All API calls require a Bearer token header:
```
Authorization: Bearer {{MC_AGENT_TOKEN}}
```

## Quick Reference

### Get your tasks
```
GET {{MC_URL}}/api/tasks?agentId={{MC_AGENT_ID}}
Authorization: Bearer {{MC_AGENT_TOKEN}}
```

### Update task status
```
PATCH {{MC_URL}}/api/tasks/<id>
{"status": "todo"|"inprogress"|"review"|"done"|"blocked"}
```

### Add a comment
```
POST {{MC_URL}}/api/tasks/<id>/comments
{"text": "Done! @human please review.", "agentId": "{{MC_AGENT_ID}}"}
```

### Create a task
```
POST {{MC_URL}}/api/tasks
{"title": "...", "agentId": "{{MC_AGENT_ID}}", "priority": "high"|"medium"|"low"}
```

## Status Flow
todo → inprogress → review → done
