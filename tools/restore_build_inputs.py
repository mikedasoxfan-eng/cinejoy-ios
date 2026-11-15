"""Preserve mtimes only for byte-identical inputs in a restored build cache."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

manifest = Path("build/input-mtimes.json")
try:
    previous = json.loads(manifest.read_text())
except (OSError, ValueError):
    previous = {}
current = {}
restored = 0
for raw in subprocess.check_output(["git", "ls-files", "-z"]).split(b"\0"):
    if not raw:
        continue
    path = Path(os.fsdecode(raw))
    if not path.is_file():
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    old = previous.get(path.as_posix())
    if old and old[0] == digest:
        os.utime(path, ns=(path.stat().st_atime_ns, old[1]))
        restored += 1
    current[path.as_posix()] = [digest, path.stat().st_mtime_ns]
manifest.parent.mkdir(parents=True, exist_ok=True)
manifest.write_text(json.dumps(current))
print(f"Reused timestamps for {restored} unchanged build inputs")
