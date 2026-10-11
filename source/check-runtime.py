"""Check the packaged native libraries without starting a Wine server."""
import os
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
engine = root / "Runtime/WineCX"
frameworks = root / "Runtime/Frameworks"
gst = frameworks / "GStreamer.framework/Versions/1.0/lib"
native = engine / "lib/wine/x86_64-unix"
search = [native, frameworks, gst]
pending = list((engine / "bin").iterdir()) + list(native.glob("*.so"))
pending += list(frameworks.glob("*.dylib")) + list(gst.glob("*.dylib"))
checked = set()
missing = []
while pending:
    path = pending.pop().resolve()
    if path in checked or not path.is_file():
        continue
    checked.add(path)
    result = subprocess.run(["/usr/bin/otool", "-L", str(path)], capture_output=True, text=True, check=True)
    for line in result.stdout.splitlines():
        match = re.match(r"\s+(.*?) \(compatibility version", line)
        if not match:
            continue
        dependency = match[1]
        if dependency.startswith(("/usr/lib/", "/System/Library/")):
            continue  # These are supplied by macOS's shared library cache.
        if dependency.startswith("@loader_path/"):
            candidates = [path.parent / dependency.removeprefix("@loader_path/")]
        elif dependency.startswith("@executable_path/"):
            candidates = [engine / "bin" / dependency.removeprefix("@executable_path/")]
        elif dependency.startswith("@rpath/"):
            suffix = dependency.removeprefix("@rpath/")
            candidates = [path.parent / suffix] + [folder / suffix for folder in search]
        elif dependency.startswith("/"):
            candidates = [Path(dependency)]
        else:
            continue
        found = next((candidate for candidate in candidates if candidate.is_file()), None)
        if found is None:
            missing.append(f"{path.name}: {dependency}")
        else:
            pending.append(found)
assert not missing, "Missing native dependencies:\n" + "\n".join(sorted(set(missing)))

environment = os.environ.copy()
environment["DYLD_FALLBACK_LIBRARY_PATH"] = f"{frameworks}:{gst}"
environment["DYLD_FALLBACK_FRAMEWORK_PATH"] = str(frameworks)
for name in ["wine", "wineserver"]:
    result = subprocess.run([str(engine / "bin" / name), "--version"], env=environment,
                            capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"{name} could not start: {result.stderr}"
print(f"PASS: native dependency paths ({len(checked)} files), Wine and wineserver startup.")
