#!/usr/bin/env python3
import json
import shutil
import stat
from datetime import datetime
from pathlib import Path


HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
ISLAND_DIR = CLAUDE_DIR / "claude-island"
SETTINGS_PATH = CLAUDE_DIR / "settings.json"
BACKUP_DIR = CLAUDE_DIR / "backups"
HOOK_DEST = ISLAND_DIR / "claude-island-hook.sh"
HOOK_SOURCE = Path(__file__).resolve().parent / "claude-island-hook.sh"


def read_settings() -> dict:
    if not SETTINGS_PATH.exists() or SETTINGS_PATH.stat().st_size == 0:
        return {}
    with SETTINGS_PATH.open("r", encoding="utf-8") as file:
        return json.load(file)


def hook_exists(entries: list) -> bool:
    for entry in entries:
        for hook in entry.get("hooks", []):
            command = hook.get("command", "")
            if hook.get("type") == "command" and "claude-island-hook.sh" in command:
                return True
    return False


def main() -> None:
    ISLAND_DIR.mkdir(parents=True, exist_ok=True)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)

    shutil.copy2(HOOK_SOURCE, HOOK_DEST)
    HOOK_DEST.chmod(HOOK_DEST.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    status_path = ISLAND_DIR / "status.json"
    status_path.write_text(
        json.dumps(
            {
                "state": "offline",
                "updatedAt": int(datetime.now().timestamp()),
                "event": "install",
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    settings = read_settings()
    backup_path = None
    if SETTINGS_PATH.exists():
        backup_path = BACKUP_DIR / f"settings.claude-island.{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
        shutil.copy2(SETTINGS_PATH, backup_path)

    hooks = settings.setdefault("hooks", {})
    events = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "Notification",
        "PermissionRequest",
        "PermissionDenied",
        "Stop",
        "StopFailure",
        "SubagentStart",
        "SubagentStop",
    ]

    for event in events:
        entries = hooks.setdefault(event, [])
        if not hook_exists(entries):
            entries.append(
                {
                    "matcher": "",
                    "hooks": [
                        {
                            "type": "command",
                            "command": f"{HOOK_DEST} {event}",
                        }
                    ],
                }
            )

    SETTINGS_PATH.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print("Installed Claude Island hooks.")
    print(f"Hook script: {HOOK_DEST}")
    if backup_path:
        print(f"Backup: {backup_path}")


if __name__ == "__main__":
    main()
