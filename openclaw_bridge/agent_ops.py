from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any, Dict


OPENCLAW_DIR = Path.home() / ".openclaw"


def _is_valid_cron(value: str) -> bool:
    # Lightweight 5-field cron validation for bridge-side safety.
    parts = value.strip().split()
    if len(parts) != 5:
        return False
    allowed = set("0123456789*,-/LW?#")
    for field in parts:
        if not field:
            return False
        if any(ch not in allowed for ch in field):
            return False
    return True


def _validate_settings_updates(updates: Dict[str, Any]) -> None:
    if "board_check_cron" in updates:
        cron = str(updates.get("board_check_cron") or "").strip()
        if cron and not _is_valid_cron(cron):
            raise ValueError("Invalid board_check_cron format; expected 5-field cron")
    if "standup_cron" in updates:
        cron = str(updates.get("standup_cron") or "").strip()
        if cron and not _is_valid_cron(cron):
            raise ValueError("Invalid standup_cron format; expected 5-field cron")
    if "timezone" in updates:
        tz = str(updates.get("timezone") or "").strip()
        if not tz:
            raise ValueError("timezone cannot be empty")


def _meta_path(agent_id: str) -> Path:
    return OPENCLAW_DIR / "agents" / agent_id / "collabai" / "agent.json"


def read_agent_meta(agent_id: str) -> Dict[str, Any]:
    path = _meta_path(agent_id)
    if not path.exists():
        raise FileNotFoundError(f"Agent not found: {agent_id}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def write_agent_meta(agent_id: str, meta: Dict[str, Any]) -> None:
    path = _meta_path(agent_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    meta["updated_at"] = int(time.time() * 1000)
    path.write_text(json.dumps(meta, ensure_ascii=True, indent=2), encoding="utf-8")


def get_agent_settings(agent_id: str) -> Dict[str, Any]:
    meta = read_agent_meta(agent_id)
    config = meta.get("config") or {}
    schedules = config.get("schedules") or {}
    return {
        "agent_id": agent_id,
        "board_check_cron": schedules.get("board_check_cron", ""),
        "standup_cron": schedules.get("standup_cron", ""),
        "timezone": schedules.get("timezone", "UTC"),
        "board_check_enabled": bool(schedules.get("board_check_enabled", False)),
        "standup_enabled": bool(schedules.get("standup_enabled", False)),
    }


def update_agent_settings(agent_id: str, updates: Dict[str, Any]) -> Dict[str, Any]:
    _validate_settings_updates(updates)
    meta = read_agent_meta(agent_id)
    config = meta.get("config") or {}
    schedules = config.get("schedules") or {}

    allowed_keys = {
        "board_check_cron",
        "standup_cron",
        "timezone",
        "board_check_enabled",
        "standup_enabled",
    }
    for key, value in updates.items():
        if key in allowed_keys and value is not None:
            schedules[key] = value

    config["schedules"] = schedules
    meta["config"] = config
    write_agent_meta(agent_id, meta)
    return get_agent_settings(agent_id)
