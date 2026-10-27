"""Package committed files only, excluding local configs and build debris."""

import hashlib
from pathlib import Path
import plistlib
import stat
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=ROOT)


def main():
    plist = plistlib.loads(git("show", "HEAD:macos/Codex Launcher.app/Contents/Info.plist"))
    version = plist["CFBundleShortVersionString"]
    prefix = f"codex-local-proxy-launcher-v{version}"
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    entries = []
    for record in git("ls-tree", "-rz", "HEAD").split(b"\0"):
        if record:
            metadata, path = record.split(b"\t", 1)
            mode, _, object_id = metadata.decode().split()
            entries.append((mode, object_id, path.decode()))

    checksums = []
    for platform in ("macos", "windows"):
        archive = output / f"{prefix}-{platform}.zip"
        directories = set()
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
            for mode, object_id, path in entries:
                if path not in ("README.md", "LICENSE", "codex-proxy-launcher.env.example") and not path.startswith((platform + "/", "docs/images/")):
                    continue
                if mode not in ("100644", "100755"):
                    raise ValueError(f"Unexpected file type in release: {path}")
                destination = f"{prefix}/{path}"
                for parent in reversed(Path(destination).parents):
                    directory = parent.as_posix()
                    if directory == "." or directory in directories:
                        continue
                    info = zipfile.ZipInfo(directory + "/")
                    info.create_system = 3
                    info.external_attr = (stat.S_IFDIR | 0o755) << 16 | 0x10
                    bundle.writestr(info, b"")
                    directories.add(directory)
                data = git("cat-file", "blob", object_id)
                if platform == "windows" and path.endswith((".ps1", ".cmd")):
                    data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
                info = zipfile.ZipInfo(destination)
                info.create_system = 3
                permissions = 0o755 if mode == "100755" else 0o644
                info.external_attr = (stat.S_IFREG | permissions) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                bundle.writestr(info, data)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        checksums.append(f"{digest}  {archive.name}\n")
        print(f"Created {archive.name}")
    (output / "SHA256SUMS").write_text("".join(checksums), encoding="ascii")


if __name__ == "__main__":
    main()
