import importlib
import os
import subprocess
import sys

from check50.__main__ import install_dependencies


dependency = os.environ.get("CS50_UV_DEPENDENCY")
if not dependency or not dependency.strip():
    raise SystemExit(
        "CS50_UV_DEPENDENCY must be a non-empty dependency specification"
    )
if any(
    ord(character) < 0x20 or 0x7F <= ord(character) <= 0x9F
    for character in dependency
):
    raise SystemExit(
        "CS50_UV_DEPENDENCY must not contain control characters"
    )

install_dependencies([dependency])
dependency_module = importlib.import_module("cs50_uv_dependency")

if getattr(dependency_module, "value", None) != "uv-installed":
    raise RuntimeError(
        "cs50_uv_dependency.value did not contain the expected value"
    )
virtual_environment = os.environ.get("VIRTUAL_ENV")
path_entries = os.environ.get("PATH", "").split(os.pathsep)
if not virtual_environment or not path_entries:
    raise RuntimeError("uv dependency environment was not activated")
if path_entries[0] != os.path.join(virtual_environment, "bin"):
    raise RuntimeError("uv dependency environment is not first on PATH")

child_environment = os.environ.copy()
child_environment["PYTHONPATH"] = os.pathsep.join(
    dict.fromkeys(path for path in sys.path if path)
)
subprocess.run(
    [
        sys.executable,
        "-c",
        (
            "import cs50_uv_dependency, sys; "
            "sys.exit(0 if cs50_uv_dependency.value == 'uv-installed' else 1)"
        ),
    ],
    check=True,
    env=child_environment,
)
