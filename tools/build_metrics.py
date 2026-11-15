"""Record real build times alongside each IPA; never estimate warm-build speed."""
import json
import os
import subprocess
import time
from pathlib import Path

def main():
    started = int(os.environ["BUILD_STARTED"])
    compile_started = int(os.environ["COMPILE_STARTED"])
    compile_finished = int(os.environ["COMPILE_FINISHED"])
    print(json.dumps({
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "compile_seconds": compile_finished - compile_started,
        "package_and_checks_seconds": int(time.time()) - compile_finished,
        "total_seconds": int(time.time()) - started,
        "ipa_bytes": Path("dist/Cinejoy-unsigned.ipa").stat().st_size,
        "configuration": "Release, optimized " + os.environ.get("COMPILE_MODE", "incremental") + ", unsigned arm64",
    }, indent=2))

if __name__ == "__main__":
    main()
