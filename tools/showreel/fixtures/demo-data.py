#!/usr/bin/env python3
"""Sample content for the clips that open things inside apps, run in the VM by
a scene's `prepare` step (apps are quit by then):

- ~/Projects/<name> folders, which VS Code lists as recent projects and Claude
  Code sessions run in;
- Claude Code sessions in those projects — history entries plus minimal
  transcripts, so `claude --resume <id>` reopens them — stamped relative to
  now, so they always read as recent;
- the folders marked trusted, so Claude Code doesn't ask on camera.

The VM's own Claude history and settings are backed up once (*.before-showreel)
before the first overwrite.
"""

import json
import shutil
import sqlite3
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
PROJECTS = HOME / "Projects"
CLAUDE_VERSION = "2.1.285"
MODEL = "claude-opus-5-5"

PROJECT_FILES = {
    "forecast-api": {
        "README.md": "# forecast-api\n\nForecast service behind the weather widget.\n",
        "src/server.ts": "import { forecast } from './forecast'\n\nexport const routes = { '/forecast': forecast }\n",
    },
    "vibeshed-site": {
        "README.md": "# vibeshed-site\n\nThe landing page for Vibeshed.\n",
        "index.html": "<!doctype html>\n<title>Vibeshed</title>\n",
    },
    "design-tokens": {
        "README.md": "# design-tokens\n\nColors, type and spacing shared by every app.\n",
        "tokens/color.json": '{ "accent": "#ff6b8b", "background": "#120d16" }\n',
    },
    "dotfiles": {
        "README.md": "# dotfiles\n\nzsh, git and editor settings.\n",
        ".zshrc": "autoload -Uz compinit && compinit\n",
    },
}

# (project, minutes ago, prompt, reply)
SESSIONS = [
    ("forecast-api", 6,
     "Add rate limiting to the /forecast endpoint: 60 requests a minute per API key",
     "I'll add a token-bucket limiter as middleware in `src/server.ts`, keyed by API key, "
     "returning 429 with a `Retry-After` header when the bucket is empty. Tests next."),
    ("vibeshed-site", 42,
     "Make the hero video loop seamlessly in Safari",
     "Safari shows a one-frame gap at the loop point when the last frame differs from the "
     "first. I re-exported the clip with a crossfade into its opening frames and added "
     "`playsinline muted autoplay loop` so it starts on iOS too."),
    ("design-tokens", 185,
     "Generate dark-mode variants for every color token",
     "Done: each token now has a `dark` value derived in OKLCH, keeping hue and lowering "
     "lightness, with contrast checked against the background tokens (all pass AA)."),
    ("dotfiles", 1500,
     "Why does my zsh prompt take 400ms to render?",
     "Most of it is `compinit` re-checking completions on every shell. Caching with "
     "`compinit -C` when the dump is under a day old brings the prompt to about 40ms."),
]


def iso(ms: float) -> str:
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def back_up(path: Path) -> None:
    backup = path.with_name(path.name + ".before-showreel")
    if path.exists() and not backup.exists():
        shutil.copy2(path, backup)


def make_projects() -> None:
    for name, files in PROJECT_FILES.items():
        for relative, text in files.items():
            file = PROJECTS / name / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(text)


def write_sessions() -> None:
    claude = HOME / ".claude"
    claude.mkdir(exist_ok=True)
    history = claude / "history.jsonl"
    back_up(history)
    now = time.time() * 1000
    lines = []
    for index, (project, minutes_ago, prompt, reply) in enumerate(SESSIONS):
        cwd = str(PROJECTS / project)
        session = str(uuid.uuid5(uuid.NAMESPACE_URL, f"showreel/{project}"))
        start = now - minutes_ago * 60_000
        lines.append(json.dumps({
            "display": prompt, "pastedContents": {}, "timestamp": int(start),
            "project": cwd, "sessionId": session,
        }))
        user_id, reply_id = str(uuid.uuid4()), str(uuid.uuid4())
        common = {
            "isSidechain": False, "userType": "external", "cwd": cwd, "sessionId": session,
            "version": CLAUDE_VERSION, "gitBranch": "main",
        }
        transcript = [
            {**common, "parentUuid": None, "type": "user", "uuid": user_id, "timestamp": iso(start),
             "message": {"role": "user", "content": prompt}},
            {**common, "parentUuid": user_id, "type": "assistant", "uuid": reply_id,
             "timestamp": iso(start + 20_000), "requestId": f"req_showreel{index}",
             "message": {
                 "id": f"msg_showreel{index}", "type": "message", "role": "assistant", "model": MODEL,
                 "content": [{"type": "text", "text": reply}], "stop_reason": "end_turn",
                 "stop_sequence": None, "usage": {"input_tokens": 1200, "output_tokens": 180},
             }},
        ]
        folder = claude / "projects" / cwd.replace("/", "-").replace(".", "-")
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{session}.jsonl").write_text("".join(json.dumps(line) + "\n" for line in transcript))
    history.write_text("".join(line + "\n" for line in lines))


def trust_projects() -> None:
    settings = HOME / ".claude.json"
    back_up(settings)
    data = json.loads(settings.read_text()) if settings.exists() else {}
    data.setdefault("hasCompletedOnboarding", True)
    projects = data.setdefault("projects", {})
    for name in PROJECT_FILES:
        entry = projects.setdefault(str(PROJECTS / name), {})
        entry["hasTrustDialogAccepted"] = True
        entry["hasCompletedProjectOnboarding"] = True
    settings.write_text(json.dumps(data, indent=2))


def vscode_recents() -> None:
    db = HOME / "Library/Application Support/Code/User/globalStorage/state.vscdb"
    if not db.exists():
        return
    entries = [{"folderUri": (PROJECTS / name).as_uri()} for name in PROJECT_FILES]
    with sqlite3.connect(db) as connection:
        connection.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            ("history.recentlyOpenedPathsList", json.dumps({"entries": entries})),
        )


if __name__ == "__main__":
    make_projects()
    write_sessions()
    trust_projects()
    vscode_recents()
    print(f"demo data: {len(PROJECT_FILES)} projects, {len(SESSIONS)} Claude sessions")
