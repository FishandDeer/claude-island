#!/usr/bin/env python3
import json
import shutil
from datetime import datetime
from pathlib import Path


HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
SETTINGS_PATH = CLAUDE_DIR / "settings.json"
BACKUP_DIR = CLAUDE_DIR / "backups"


def main() -> None:
    if not SETTINGS_PATH.exists():
        print("No Claude Code settings file found.")
        return

    settings = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
    backup_path = BACKUP_DIR / f"settings.claude-island-uninstall.{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SETTINGS_PATH, backup_path)

    hooks = settings.get("hooks", {})
    for event, entries in list(hooks.items()):
        filtered_entries = []
        for entry in entries:
            hook_items = entry.get("hooks", [])
            filtered_hooks = [
                hook
                for hook in hook_items
                if "claude-island-hook.sh" not in hook.get("command", "")
            ]
            if filtered_hooks:
                entry["hooks"] = filtered_hooks
                filtered_entries.append(entry)

        if filtered_entries:
            hooks[event] = filtered_entries
        else:
            hooks.pop(event, None)

    if hooks:
        settings["hooks"] = hooks
    else:
        settings.pop("hooks", None)

    SETTINGS_PATH.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Removed Claude Island hooks.")
    print(f"Backup: {backup_path}")


if __name__ == "__main__":
    main()
