import base64
import hashlib
import os
from pathlib import Path
import zipfile

if os.environ.get("CS50_TEST_INHERITED_MARKER"):
    raise RuntimeError("dynamic dependency installer leaked caller environment")


NAME = "cs50_uv_dependency"
VERSION = "0.0.0"
DIST_INFO = f"{NAME}-{VERSION}.dist-info"
WHEEL_NAME = f"{NAME}-{VERSION}-py3-none-any.whl"


def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):
    wheel_path = Path(wheel_directory) / WHEEL_NAME
    files = {
        f"{NAME}/__init__.py": 'value = "uv-installed"\n',
        f"{DIST_INFO}/METADATA": "Metadata-Version: 2.1\nName: cs50-uv-dependency\nVersion: 0.0.0\n",
        f"{DIST_INFO}/WHEEL": "Wheel-Version: 1.0\nGenerator: cs50-uv-smoke\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
    }

    records = []
    with zipfile.ZipFile(wheel_path, "w", zipfile.ZIP_DEFLATED) as wheel:
        for filename, content in files.items():
            data = content.encode()
            wheel.writestr(filename, data)
            digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
            records.append(f"{filename},sha256={digest},{len(data)}")
        records.append(f"{DIST_INFO}/RECORD,,")
        wheel.writestr(f"{DIST_INFO}/RECORD", "\n".join(records) + "\n")

    return WHEEL_NAME
