#!/usr/bin/env python3
"""Build in a private workspace; publish and retire artifacts only after success."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
import unicodedata
import zipfile

APP = "Mac优化大师.app"
EXECUTABLE = "AppUninstaller"
MANIFEST = ".macoptimizer-build-manifest.json"
MEDIA = {".png", ".jpg", ".jpeg", ".icns", ".m4a", ".mp4"}
VERSION = r"[0-9]+(?:\.[0-9]+)*"
LEGACY_RELEASE = re.compile(r"release-(" + VERSION + r")-build([0-9]+)")
LEGACY_BACKUP = re.compile(r"MacOptimizer_v(" + VERSION + r")_build([0-9]+)_before_build[0-9]+_[0-9]{8}T[0-9]{6}Z\.zip")


def run(command, **kwargs):
    kwargs.setdefault("check", True)
    return subprocess.run([str(value) for value in command], **kwargs)


def safe_path(path, root):
    """Reject symbolic links in the managed path without following descendants."""
    path, root = Path(path), Path(root)
    relative = path.relative_to(root)
    current = root
    for part in ("", *relative.parts):
        if part:
            current /= part
        if current.is_symlink():
            raise ValueError(f"Refusing symbolic link: {current}")
    return path


@contextmanager
def packaging_lock(repo):
    directory = safe_path(repo / ".build", repo)
    directory.mkdir(exist_ok=True)
    path = safe_path(directory / "packaging.lock", repo)
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another MacOptimizer packaging process is running") from None
        yield


def artifact_path(value):
    path = Path(value)
    parts = path.parts
    if path.is_absolute() or not parts or any(part in (".", "..") for part in parts):
        return False
    return (value == APP or value == "Mac优化大师.dmg" or value == "backups/previous-install.zip"
            or (len(parts) == 2 and parts[0] in ("arm64", "x86_64") and parts[1] == APP)
            or (len(parts) == 1 and re.fullmatch(r"Mac优化大师_v" + VERSION + r"_(?:AppleSilicon|Intel)\.dmg", value) is not None))


def read_manifest(output):
    path = safe_path(output / MANIFEST, output)
    if not path.exists():
        return []
    value = json.loads(path.read_text())
    if value.get("schema") != 1 or not isinstance(value.get("artifacts"), list):
        raise ValueError("Invalid build artifact manifest")
    entries = value["artifacts"]
    if any(not isinstance(item, dict) or not isinstance(item.get("path"), str)
           or not artifact_path(item["path"]) or item.get("kind") not in ("app", "dmg", "backup") for item in entries):
        raise ValueError("Unsafe build artifact manifest")
    return entries



def legacy_flat_artifacts(output, bundle_id):
    """Adopt only old DMGs paired with their architecture's verified bundle info."""
    entries = []
    for arch, label in (("arm64", "AppleSilicon"), ("x86_64", "Intel")):
        app = output / arch / APP
        try:
            safe_path(app / "Contents/Info.plist", output)
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            version, build = str(info.get("CFBundleShortVersionString", "")), str(info.get("CFBundleVersion", ""))
            if (info.get("CFBundleIdentifier") != bundle_id or info.get("CFBundleExecutable") != EXECUTABLE
                    or not re.fullmatch(VERSION, version) or not build.isdigit()):
                continue
            name = f"Mac优化大师_v{version}_{label}.dmg"
            dmg = safe_path(output / name, output)
            if dmg.is_file():
                entries.append({"path": name, "kind": "dmg"})
        except (OSError, ValueError, plistlib.InvalidFileException):
            continue
    return entries


def build_app(repo, stage, arch, metadata, sdk, module_cache):
    source = repo / "AppUninstaller"
    app = stage / arch / APP
    executable = app / "Contents/MacOS" / EXECUTABLE
    resources = app / "Contents/Resources"
    executable.parent.mkdir(parents=True)
    resources.mkdir(parents=True)
    shutil.copy2(source / "Info.plist", app / "Contents/Info.plist")
    for item in source.iterdir():
        if item.is_file() and item.suffix.lower() in MEDIA:
            shutil.copy2(item, resources / item.name)
    localizations = source / "Localizations"
    if localizations.is_dir():
        for item in localizations.glob("*.lproj"):
            shutil.copytree(item, resources / item.name, symlinks=True)
    sources = sorted(source.rglob("*.swift"))
    if not sources:
        raise ValueError("No Swift source files found")
    run(["xcrun", "swiftc", "-O", "-whole-module-optimization", "-target", f"{arch}-apple-macos13.0",
         "-sdk", sdk, "-module-cache-path", module_cache, "-parse-as-library", "-o", executable, *sources])
    run(["codesign", "--force", "--deep", "--sign", "-", app])
    run(["codesign", "--verify", "--deep", "--strict", app])
    run(["lipo", "-verify_arch", arch, executable])
    return app



def emit_output(result):
    for value, stream in ((result.stdout, sys.stdout), (result.stderr, sys.stderr)):
        if value:
            print(value, end="" if value.endswith("\n") else "\n", file=stream, flush=True)


def build_dmg(repo, stage, app, arch, name):
    content = stage / f"dmg-content-{arch}"
    content.mkdir()
    shutil.copytree(app, content / APP, symlinks=True)
    (content / "Applications").symlink_to("/Applications")
    background = repo / "dmg_background.png"
    if background.is_file():
        (content / ".background").mkdir()
        shutil.copy2(background, content / ".background/background.png")
    dmg = stage / name
    command = ["hdiutil", "create", "-volname", "Mac优化大师", "-srcfolder", content,
               "-ov", "-format", "UDZO", "-imagekey", "zlib-level=9", dmg]
    for attempt in range(3):
        try:
            result = run(command, capture_output=True, text=True)
        except subprocess.CalledProcessError as error:
            message = (error.stderr or "").lower()
            busy = any(value in message for value in ("resource busy", "device busy", "资源忙", "资源正忙"))
            if not busy or attempt == 2:
                emit_output(error)
                raise
            dmg.unlink(missing_ok=True)
            print(f"DMG creation is busy; retrying in {attempt + 1}s…", file=sys.stderr, flush=True)
            time.sleep(attempt + 1)
        else:
            emit_output(result)
            break
    run(["hdiutil", "verify", dmg])
    return dmg


def remove_artifact(path, output):
    safe_path(path, output)
    if path.is_dir():
        shutil.rmtree(path)  # rmtree unlinks internal symbolic links; it does not traverse them.
    elif path.exists():
        path.unlink()


def matching_app(path, version, build, bundle_id):
    try:
        if path.is_symlink() or not path.is_dir():
            return False
        info = path / "Contents/Info.plist"
        safe_path(info, path)
        value = plistlib.loads(info.read_bytes())
        return (value.get("CFBundleIdentifier") == bundle_id
                and str(value.get("CFBundleShortVersionString")) == version
                and str(value.get("CFBundleVersion")) == build)
    except (OSError, ValueError, plistlib.InvalidFileException):
        return False


def archive_entry(archive, expected):
    """ditto may store UTF-8 names without setting ZIP's UTF-8 flag."""
    expected = unicodedata.normalize("NFC", expected)
    matches = []
    for entry in archive.infolist():
        names = [entry.filename]
        if not entry.flag_bits & 0x800:
            try:
                names.append(entry.filename.encode("cp437").decode("utf-8"))
            except (UnicodeEncodeError, UnicodeDecodeError):
                pass
        if any(unicodedata.normalize("NFC", name) == expected for name in names):
            matches.append(entry)
    if len(matches) != 1:
        raise RuntimeError(f"Expected one rollback archive entry: {expected}")
    return matches[0]


def matching_backup(path, match, bundle_id):
    try:
        if path.is_symlink() or not path.is_file():
            return False
        with zipfile.ZipFile(path) as archive:
            entry = archive_entry(archive, APP + "/Contents/Info.plist")
            if entry.file_size > 1_000_000:
                return False
            info = plistlib.loads(archive.read(entry))
        return (info.get("CFBundleIdentifier") == bundle_id
                and str(info.get("CFBundleShortVersionString")) == match[1]
                and str(info.get("CFBundleVersion")) == match[2])
    except (OSError, ValueError, RuntimeError, NotImplementedError, zipfile.BadZipFile, plistlib.InvalidFileException):
        return False



def verified_rollback(path, bundle_id):
    try:
        if path.is_symlink() or not path.is_file():
            return False
        with zipfile.ZipFile(path) as archive:
            entry = archive_entry(archive, APP + "/Contents/Info.plist")
            if entry.file_size > 1_000_000:
                return False
            info = plistlib.loads(archive.read(entry))
            binary = archive_entry(archive, APP + "/Contents/MacOS/" + EXECUTABLE)
            return (info.get("CFBundleIdentifier") == bundle_id
                    and info.get("CFBundleExecutable") == EXECUTABLE
                    and binary.file_size > 0 and archive.testzip() is None)
    except (OSError, KeyError, ValueError, RuntimeError, NotImplementedError, zipfile.BadZipFile, plistlib.InvalidFileException):
        return False


def app_is_running(app, processes):
    prefix = str(app) + "/Contents/"
    return any(executable.startswith(prefix) for executable in processes)


def prune(output, previous, current, bundle_id, processes=()):
    keep = {item["path"] for item in current}
    for item in previous:
        if item["path"] not in keep:
            if item["kind"] == "app" and app_is_running(output / item["path"], processes):
                print(f"Warning: keeping running build {output / item['path']}", file=sys.stderr)
                continue
            remove_artifact(output / item["path"], output)
    # Historical builds predate the manifest. Remove only verified packages,
    # leaving diagnostics and any files that are not recognized build products.
    for directory in output.iterdir():
        match = LEGACY_RELEASE.fullmatch(directory.name)
        if not match or directory.is_symlink() or not directory.is_dir():
            continue
        safe_path(directory, output)
        app = directory / APP
        if app_is_running(app, processes):
            print(f"Warning: keeping running build and paired DMG: {app}", file=sys.stderr)
            continue
        if matching_app(app, match[1], match[2], bundle_id):
            remove_artifact(app, output)
            dmg = directory / f"MacOptimizer_v{match[1]}_build{match[2]}_AppleSilicon.dmg"
            if dmg.is_file() and not dmg.is_symlink():
                remove_artifact(dmg, output)
        if not any(directory.iterdir()):
            directory.rmdir()
    backups = output / "backups"
    if backups.exists():
        safe_path(backups, output)
        replacement = safe_path(backups / "previous-install.zip", output)
        if not verified_rollback(replacement, bundle_id):
            return
        for item in backups.iterdir():
            match = LEGACY_BACKUP.fullmatch(item.name)
            if match and matching_backup(item, match, bundle_id):
                remove_artifact(item, output)


def publish(output, work, staged, metadata, entries):
    """Move all outputs as one recoverable transaction, including the manifest."""
    manifest = work / MANIFEST
    manifest.write_text(json.dumps({"schema": 1, "version": metadata["CFBundleShortVersionString"],
                                   "build": metadata["CFBundleVersion"], "artifacts": entries}, ensure_ascii=False, indent=2) + "\n")
    moves = [*staged, (manifest, MANIFEST)]
    for _, relative in moves:
        safe_path(output / relative, output)
    # Recovery data must outlive TemporaryDirectory even if restoring it fails.
    old = output / (".macoptimizer-recovery-" + uuid.uuid4().hex)
    old.mkdir()
    replaced, installed = [], []
    try:
        for source, relative in moves:
            target = output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                backup = old / relative
                backup.parent.mkdir(parents=True, exist_ok=True)
                os.replace(target, backup)
                replaced.append((backup, target))
            os.replace(source, target)
            installed.append(target)
    except BaseException:
        errors = []
        for target in reversed(installed):
            try:
                remove_artifact(target, output)
            except (OSError, ValueError) as error:
                errors.append(str(error))
        for backup, target in reversed(replaced):
            try:
                os.replace(backup, target)
            except OSError as error:
                errors.append(str(error))
        if errors:
            print(f"Recovery incomplete; previous artifacts retained at {old}: {'; '.join(errors)}", file=sys.stderr)
        else:
            shutil.rmtree(old)
        raise
    try:
        shutil.rmtree(old)
    except OSError as error:
        print(f"Warning: previous artifact cleanup retained {old}: {error}", file=sys.stderr)


def package(repo, arch, install, install_dir):
    output = safe_path(repo / ("build_release" if arch == "both" else "build"), repo)
    with packaging_lock(repo):
        output.mkdir(exist_ok=True)
        previous = read_manifest(output)
        metadata = plistlib.loads((repo / "AppUninstaller/Info.plist").read_bytes())
        version, build = str(metadata["CFBundleShortVersionString"]), str(metadata["CFBundleVersion"])
        if (not re.fullmatch(VERSION, version) or not build.isdigit()
                or not metadata.get("CFBundleIdentifier") or metadata.get("CFBundleExecutable") != EXECUTABLE):
            raise ValueError("Invalid application identity/version/build")
        if arch == "both" and not (output / MANIFEST).exists():
            previous = legacy_flat_artifacts(output, metadata["CFBundleIdentifier"])
        archs = ["arm64", "x86_64"] if arch == "both" else [arch]
        native = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64"
        if install and native not in archs:
            raise ValueError("Installation requires a build for this Mac's architecture")
        with tempfile.TemporaryDirectory(prefix=".macoptimizer-package-", dir=output) as temporary:
            work = Path(temporary)
            sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()
            staged, entries, apps = [], [], {}
            for selected in archs:
                print(f"Compiling {selected}…", flush=True)
                app = build_app(repo, work, selected, metadata, sdk, work / "module-cache")
                name = f"Mac优化大师_v{version}_{'AppleSilicon' if selected == 'arm64' else 'Intel'}.dmg" if arch == "both" else "Mac优化大师.dmg"
                print(f"Packaging {selected} DMG…", flush=True)
                dmg = build_dmg(repo, work, app, selected, name)
                relative_app = f"{selected}/{APP}" if arch == "both" else APP
                staged.extend([(app, relative_app), (dmg, name)])
                entries.extend([{"path": relative_app, "kind": "app"}, {"path": name, "kind": "dmg"}])
                apps[selected] = app
            snapshot = run(["/bin/ps", "-axww", "-o", "comm="], capture_output=True, text=True).stdout
            processes = tuple(line.strip() for line in snapshot.splitlines() if line.strip())
            for item in entries:
                if item["kind"] == "app" and app_is_running(output / item["path"], processes):
                    raise RuntimeError(f"Quit the running output application before replacing it: {output / item['path']}")
            transaction = None
            if install:
                sys.path.insert(0, str(Path(__file__).parent))
                from install_built_app import install_app
                transaction = install_app(apps[native], Path(install_dir) / APP, work, run)
            try:
                rollback = "backups/previous-install.zip"
                if transaction is not None and transaction.backup is not None:
                    staged.append((Path(transaction.backup), rollback))
                    entries.append({"path": rollback, "kind": "backup"})
                elif (output / rollback).exists():
                    safe_path(output / rollback, output)
                    entries.append({"path": rollback, "kind": "backup"})
                publish(output, work, staged, metadata, entries)
            except BaseException:
                if transaction is not None:
                    transaction.rollback()
                raise
            if transaction is not None:
                if transaction.backup is not None:
                    transaction.backup = output / rollback
                try:
                    transaction.commit()
                except Exception as error:
                    print(f"Warning: installation backup cleanup: {error}", file=sys.stderr)
                    return output
            try:
                prune(output, previous, entries, metadata["CFBundleIdentifier"], processes)
            except (OSError, ValueError) as error:
                print(f"Warning: old build cleanup: {error}", file=sys.stderr)
    return output


def main(argv=None, repo_root=None):
    parser = argparse.ArgumentParser(description="Build, package, optionally install, and retire managed MacOptimizer artifacts.")
    parser.add_argument("--arch", choices=("arm64", "x86_64", "both"), default="arm64")
    parser.add_argument("--install", action="store_true", help="Install and launch the build for this Mac")
    parser.add_argument("--install-dir", default="/Applications")
    args = parser.parse_args(argv)
    repo = Path(repo_root if repo_root is not None else Path(__file__).parent.parent).resolve()
    try:
        output = package(repo, args.arch, args.install, args.install_dir)
    except Exception as error:
        print(f"Build failed: {error}", file=sys.stderr)
        return 1
    print(f"Build completed: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
