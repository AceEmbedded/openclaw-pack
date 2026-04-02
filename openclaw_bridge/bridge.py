"""
CollabAI Agent Bridge (Python)
Runs on OpenClaw host — exposes system data + debug webhook to CollabAI cloud.

Ported from the legacy Node.js bridge.
"""

from __future__ import annotations

import asyncio
import json
import os
import platform
import shutil
import socket
import subprocess
import time
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any, Dict, List, Optional

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request
from pydantic import BaseModel
from agent_ops import get_agent_settings, update_agent_settings

try:
    from dotenv import load_dotenv

    _root_env = Path(__file__).resolve().parent.parent / ".env"
    if _root_env.is_file():
        load_dotenv(_root_env)
except ImportError:
    pass

PORT = int(os.getenv("BRIDGE_PORT", "3334"))
AGENT_TOKEN = os.getenv("AGENT_TOKEN", "")
WEBHOOK_TOKEN = os.getenv("WEBHOOK_TOKEN", "webhook_collabai_debug_2026")
COLLABAI_API = os.getenv("COLLABAI_API_URL", "https://api.collaba.ai").rstrip("/")
OPENCLAW_DIR = Path.home() / ".openclaw"

DEDUP_WINDOW_SECONDS = 60 * 60
_dedup_lock = asyncio.Lock()


@dataclass
class _DedupEntry:
    task_id: Optional[str]
    count: int
    last_seen: float


_dedup_cache: Dict[str, _DedupEntry] = {}


def _auth_header_token(request: Request) -> str:
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("bearer "):
        return auth[7:].strip()
    return auth.strip()


def require_agent_token(request: Request) -> None:
    token = _auth_header_token(request)
    if token != AGENT_TOKEN and token != WEBHOOK_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")


def _run_cmd(cmd: List[str], timeout_s: float = 5.0) -> Optional[str]:
    try:
        p = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout_s,
            check=False,
        )
        out = (p.stdout or "").strip()
        return out or None
    except Exception:
        return None


def _read_json(path: Path) -> Optional[dict]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _tail_file_lines(path: Path, n: int) -> List[str]:
    if n <= 0:
        return []
    try:
        with path.open("rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            block = 4096
            data = b""
            pos = size
            while pos > 0 and data.count(b"\n") <= n:
                read_size = block if pos - block > 0 else pos
                pos -= read_size
                f.seek(pos)
                data = f.read(read_size) + data
            lines = data.splitlines()[-n:]
            return [ln.decode("utf-8", errors="replace") for ln in lines]
    except Exception as e:
        return [f"Error: {e}"]


def _uptime_seconds() -> Optional[float]:
    # Linux: /proc/uptime
    try:
        p = Path("/proc/uptime")
        if p.exists():
            return float(p.read_text(encoding="utf-8").split()[0])
    except Exception:
        pass

    # macOS/BSD: sysctl kern.boottime
    if shutil.which("sysctl"):
        out = _run_cmd(["sysctl", "-n", "kern.boottime"])
        if out:
            # Example: "{ sec = 1711990000, usec = 0 } Sat Apr  1 12:34:56 2026"
            try:
                sec_part = out.split("sec = ", 1)[1].split(",", 1)[0].strip()
                boot = float(sec_part)
                return max(time.time() - boot, 0.0)
            except Exception:
                pass

    return None


def _memory_bytes() -> tuple[int, int]:
    """
    Returns (total_bytes, free_or_available_bytes) best-effort.
    """
    # Linux: /proc/meminfo
    try:
        p = Path("/proc/meminfo")
        if p.exists():
            meminfo: Dict[str, int] = {}
            for line in p.read_text(encoding="utf-8").splitlines():
                if ":" not in line:
                    continue
                k, v = line.split(":", 1)
                parts = v.strip().split()
                if not parts:
                    continue
                meminfo[k] = int(parts[0]) * 1024  # values are usually kB
            total = meminfo.get("MemTotal", 0)
            avail = meminfo.get("MemAvailable", meminfo.get("MemFree", 0))
            return total, avail
    except Exception:
        pass

    # macOS: hw.memsize and vm_stat
    total = 0
    free = 0
    if shutil.which("sysctl"):
        out = _run_cmd(["sysctl", "-n", "hw.memsize"])
        if out and out.strip().isdigit():
            total = int(out.strip())

    if shutil.which("vm_stat"):
        out = _run_cmd(["vm_stat"])
        if out:
            page_size = 4096
            for line in out.splitlines():
                if "page size of" in line:
                    try:
                        page_size = int(line.split("page size of", 1)[1].split("bytes", 1)[0].strip())
                    except Exception:
                        page_size = 4096
            pages: Dict[str, int] = {}
            for line in out.splitlines():
                if ":" not in line:
                    continue
                k, v = line.split(":", 1)
                num = "".join(ch for ch in v if ch.isdigit())
                if num:
                    pages[k.strip()] = int(num)
            free_pages = pages.get("Pages free", 0) + pages.get("Pages speculative", 0)
            free = free_pages * page_size

    if total:
        return total, free

    # Fallback: POSIX sysconf for total only
    if hasattr(os, "sysconf"):
        try:
            page = int(os.sysconf("SC_PAGE_SIZE"))
            pages = int(os.sysconf("SC_PHYS_PAGES"))
            return page * pages, 0
        except Exception:
            pass

    return 0, 0


def _dedup_key(app: str, env: str, error_type: str, task_name: str, msg: str) -> str:
    return f"{app}|{env}|{error_type}|{task_name}|{(msg or '')[:100]}"


async def _cleanup_dedup_loop() -> None:
    while True:
        await asyncio.sleep(30 * 60)
        cutoff = time.time() - DEDUP_WINDOW_SECONDS
        async with _dedup_lock:
            for k in list(_dedup_cache.keys()):
                if _dedup_cache[k].last_seen < cutoff:
                    _dedup_cache.pop(k, None)


app = FastAPI(title="CollabAI OpenClaw Bridge", version="0.1.0")


class SetupAgentRequest(BaseModel):
    agent_id: str
    agent_name: str
    agent_token: str
    description: Optional[str] = None
    config: Optional[dict] = None
    collabai_api_url: Optional[str] = None


class SetupAgentResponse(BaseModel):
    ok: bool
    agent_id: str
    agent_dir: str
    env_file: str
    cli_present: bool
    cli_exit_code: Optional[int] = None
    cli_output: Optional[str] = None


class UpdateAgentRequest(BaseModel):
    new_agent_id: Optional[str] = None
    agent_name: Optional[str] = None
    agent_token: Optional[str] = None
    description: Optional[str] = None
    config: Optional[dict] = None
    collabai_api_url: Optional[str] = None


class AgentSettingsUpdateRequest(BaseModel):
    board_check_cron: Optional[str] = None
    standup_cron: Optional[str] = None
    timezone: Optional[str] = None
    board_check_enabled: Optional[bool] = None
    standup_enabled: Optional[bool] = None


def _agent_paths(agent_id: str) -> tuple[Path, Path, Path]:
    agent_dir = OPENCLAW_DIR / "agents" / agent_id
    creds_dir = agent_dir / "collabai"
    env_file = creds_dir / ".env"
    meta_file = creds_dir / "agent.json"
    return agent_dir, env_file, meta_file


def _write_agent_files(
    agent_id: str,
    agent_name: str,
    agent_token: str,
    collabai_api_url: str,
    description: Optional[str] = None,
    config: Optional[dict] = None,
) -> tuple[Path, Path]:
    agent_dir, env_file, meta_file = _agent_paths(agent_id)
    env_file.parent.mkdir(parents=True, exist_ok=True)
    env_file.write_text(
        "\n".join(
            [
                f"COLLABAI_API_URL={collabai_api_url.rstrip('/')}",
                f"AGENT_TOKEN={agent_token}",
                f"AGENT_ID={agent_id}",
                f"AGENT_NAME={agent_name}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    meta_file.write_text(
        json.dumps(
            {
                "agent_id": agent_id,
                "agent_name": agent_name,
                "description": description or "",
                "config": config or {},
                "updated_at": int(time.time() * 1000),
            },
            ensure_ascii=True,
            indent=2,
        ),
        encoding="utf-8",
    )
    return env_file, meta_file


@app.on_event("startup")
async def _startup() -> None:
    asyncio.create_task(_cleanup_dedup_loop())


@app.get("/health")
async def health() -> dict:
    return {"ok": True, "ts": int(time.time() * 1000)}


@app.get("/api/system")
async def api_system(_: Any = Depends(require_agent_token)) -> dict:
    total_mem, free_mem = _memory_bytes()
    used_mem = max(total_mem - free_mem, 0) if total_mem else 0

    memory = {
        "total": round(total_mem / 1024 / 1024) if total_mem else 0,
        "used": round(used_mem / 1024 / 1024) if used_mem else 0,
        "pct": round((used_mem / total_mem) * 100) if total_mem else 0,
    }

    # Disk (parse `df -h /`)
    disk = None
    df = _run_cmd(["df", "-h", "/"])
    if df:
        lines = df.splitlines()
        if len(lines) >= 2:
            parts = lines[-1].split()
            if len(parts) >= 5:
                disk = {"size": parts[1], "used": parts[2], "avail": parts[3], "pct": parts[4]}

    # Gateway status (systemd user service on Linux; unknown elsewhere)
    gateway = {"status": "unknown", "pid": None}
    if shutil.which("systemctl"):
        s = _run_cmd(["systemctl", "--user", "is-active", "openclaw-gateway"])
        if s:
            gateway["status"] = "running" if s.strip() == "active" else s.strip()

    # Load average
    try:
        load_avg = list(os.getloadavg())
    except Exception:
        load_avg = []

    return {
        "hostname": socket.gethostname(),
        "platform": f"{platform.system()} {platform.machine()}",
        "uptime": _uptime_seconds(),
        "loadAvg": load_avg,
        "memory": memory,
        "disk": disk,
        "gateway": gateway,
        "timestamp": int(time.time() * 1000),
    }


@app.get("/api/openclaw/agents")
async def api_openclaw_agents(_: Any = Depends(require_agent_token)) -> List[dict]:
    agents_dir = OPENCLAW_DIR / "agents"
    agents: List[dict] = []

    # Keep parity with JS (loads openclaw.json though not used for response)
    _ = _read_json(OPENCLAW_DIR / "openclaw.json")

    try:
        for p in agents_dir.iterdir():
            if not p.is_dir():
                continue
            sess_dir = p / "sessions"
            session_files: List[Path] = []
            try:
                session_files = sorted(
                    [f for f in sess_dir.iterdir() if f.is_file() and f.name.endswith(".jsonl")],
                    key=lambda f: f.stat().st_mtime,
                    reverse=True,
                )
            except Exception:
                session_files = []

            session_count = len(session_files)
            last_active = (session_files[0].stat().st_mtime * 1000) if session_files else None
            status = "idle"
            if last_active and (time.time() * 1000 - last_active) < 300_000:
                status = "active"

            agents.append(
                {
                    "id": p.name,
                    "sessionCount": session_count,
                    "lastActive": last_active,
                    "status": status,
                    "meta": _read_json(p / "collabai" / "agent.json") or {},
                }
            )
    except Exception:
        pass

    return agents


@app.post("/api/openclaw/agents/setup", response_model=SetupAgentResponse)
async def api_openclaw_setup_agent(
    payload: SetupAgentRequest,
    _: Any = Depends(require_agent_token),
) -> SetupAgentResponse:
    """
    Prepare OpenClaw agent workspace and credentials on the VM.
    Idempotent: can be called repeatedly for the same agent.
    """
    if not payload.agent_id.strip() or not payload.agent_token.strip():
        raise HTTPException(status_code=400, detail="agent_id and agent_token are required")

    agent_id = payload.agent_id.strip()
    agent_name = (payload.agent_name or payload.agent_id).strip()
    api_url = (payload.collabai_api_url or COLLABAI_API).rstrip("/")
    env_file, _ = _write_agent_files(
        agent_id=agent_id,
        agent_name=agent_name,
        agent_token=payload.agent_token,
        collabai_api_url=api_url,
        description=payload.description,
        config=payload.config,
    )

    # Best-effort OpenClaw CLI integration if available on host.
    # We do not fail setup if CLI bootstrap command isn't present/supported.
    cli_output: Optional[str] = None
    cli_exit_code: Optional[int] = None
    cli_present = shutil.which("openclaw") is not None
    if cli_present:
        try:
            proc = subprocess.run(
                ["openclaw", "--version"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=10,
                check=False,
            )
            cli_exit_code = proc.returncode
            cli_output = (proc.stdout or "").strip()[:500]
        except Exception as e:
            cli_exit_code = 1
            cli_output = f"openclaw cli check failed: {e}"

    return SetupAgentResponse(
        ok=True,
        agent_id=agent_id,
        agent_dir=str(_agent_paths(agent_id)[0]),
        env_file=str(env_file),
        cli_present=cli_present,
        cli_exit_code=cli_exit_code,
        cli_output=cli_output,
    )


@app.patch("/api/openclaw/agents/{agent_id}")
async def api_openclaw_update_agent(
    agent_id: str,
    payload: UpdateAgentRequest,
    _: Any = Depends(require_agent_token),
) -> dict:
    """
    Dummy endpoint to update OpenClaw agent credentials/metadata.
    Supports renaming agent id and updating token/name/description/config.
    """
    current_id = agent_id.strip()
    if not current_id:
        raise HTTPException(status_code=400, detail="agent_id is required")

    old_dir, old_env, old_meta = _agent_paths(current_id)
    if not old_dir.exists():
        raise HTTPException(status_code=404, detail="Agent not found")

    target_id = (payload.new_agent_id or current_id).strip()
    if not target_id:
        raise HTTPException(status_code=400, detail="new_agent_id cannot be empty")

    if target_id != current_id:
        new_dir, _, _ = _agent_paths(target_id)
        if new_dir.exists():
            raise HTTPException(status_code=400, detail="Target agent id already exists")
        old_dir.rename(new_dir)

    _, env_file, meta_file = _agent_paths(target_id)
    existing_meta = _read_json(meta_file) or {}

    # Read current values from env file (best effort)
    current_env: Dict[str, str] = {}
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                current_env[k.strip()] = v.strip()

    final_name = payload.agent_name or current_env.get("AGENT_NAME") or existing_meta.get("agent_name") or target_id
    final_token = payload.agent_token or current_env.get("AGENT_TOKEN")
    if not final_token:
        raise HTTPException(status_code=400, detail="agent_token is required for update")
    final_api = payload.collabai_api_url or current_env.get("COLLABAI_API_URL") or COLLABAI_API
    final_description = payload.description if payload.description is not None else existing_meta.get("description", "")
    final_config = payload.config if payload.config is not None else existing_meta.get("config", {})

    _write_agent_files(
        agent_id=target_id,
        agent_name=final_name,
        agent_token=final_token,
        collabai_api_url=final_api,
        description=final_description,
        config=final_config,
    )

    return {
        "ok": True,
        "agent_id": target_id,
        "agent_dir": str(_agent_paths(target_id)[0]),
        "env_file": str(env_file),
        "meta_file": str(meta_file),
    }


@app.get("/api/openclaw/agents/{agent_id}/settings")
async def api_openclaw_get_agent_settings(
    agent_id: str,
    _: Any = Depends(require_agent_token),
) -> dict:
    try:
        return {"ok": True, **get_agent_settings(agent_id.strip())}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Agent not found") from None


@app.patch("/api/openclaw/agents/{agent_id}/settings")
async def api_openclaw_update_agent_settings(
    agent_id: str,
    payload: AgentSettingsUpdateRequest,
    _: Any = Depends(require_agent_token),
) -> dict:
    try:
        updates = payload.model_dump(exclude_unset=True)
        settings = update_agent_settings(agent_id.strip(), updates)
        return {"ok": True, **settings}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Agent not found") from None
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e


@app.get("/api/openclaw/logs")
async def api_openclaw_logs(request: Request, _: Any = Depends(require_agent_token)) -> dict:
    try:
        lines = int(request.query_params.get("lines", "80"))
    except Exception:
        lines = 80

    today = date.today().isoformat()
    log_file = Path(f"/tmp/openclaw/openclaw-{today}.log")
    if log_file.exists():
        return {"lines": _tail_file_lines(log_file, lines), "file": str(log_file)}
    return {"lines": ["No log file found"], "file": None}


@app.get("/api/openclaw/access")
async def api_openclaw_access(request: Request, _: Any = Depends(require_agent_token)) -> dict:
    host = request.url.hostname or ""
    dashboard_url = f"http://{host}:3000" if host else None
    return {
        "ok": True,
        "dashboard_url": dashboard_url,
        "token": AGENT_TOKEN or None,
    }


@app.post("/webhook/debug")
async def webhook_debug(request: Request) -> dict:
    token = request.headers.get("x-webhook-token") or _auth_header_token(request)
    if token != WEBHOOK_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid webhook token")

    body = await request.json()
    timestamp = body.get("timestamp")
    app_name = body.get("app")
    environment = body.get("environment")
    error = body.get("error") or {}
    task = body.get("task") or {}

    if not error or not app_name:
        raise HTTPException(status_code=400, detail="Missing required fields: app, error")

    env = str(environment or "UNKNOWN").upper()
    ts = timestamp or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    task_name = (task or {}).get("name") or ""
    error_type = (error or {}).get("type") or ""
    error_msg = (error or {}).get("message") or ""

    key = _dedup_key(app_name, env, error_type, task_name, error_msg)
    now = time.time()

    async with _dedup_lock:
        cached = _dedup_cache.get(key)
        if cached and (now - cached.last_seen) < DEDUP_WINDOW_SECONDS:
            cached.count += 1
            cached.last_seen = now

            # Forward dedup payload to CollabAI API (best-effort)
            try:
                async with httpx.AsyncClient(timeout=8.0) as client:
                    await client.post(
                        f"{COLLABAI_API}/api/webhook/debug",
                        headers={"Content-Type": "application/json", "x-webhook-token": WEBHOOK_TOKEN},
                        json=body,
                    )
            except Exception:
                pass

            return {
                "ok": True,
                "taskId": cached.task_id,
                "deduplicated": True,
                "occurrences": cached.count,
                "ts": ts,
            }

    # Not a dedup hit — forward and cache if task id returned
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            r = await client.post(
                f"{COLLABAI_API}/api/webhook/debug",
                headers={"Content-Type": "application/json", "x-webhook-token": WEBHOOK_TOKEN},
                json=body,
            )
            r.raise_for_status()
            data = r.json()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Failed to forward to CollabAI: {e}") from e

    task_id = data.get("task_id") or data.get("taskId")
    if task_id:
        async with _dedup_lock:
            _dedup_cache[key] = _DedupEntry(task_id=str(task_id), count=1, last_seen=now)

    return {"ok": True, **data}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT, reload=False)

