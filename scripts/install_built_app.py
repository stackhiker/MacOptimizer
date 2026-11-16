"""Install one verified bundle, retaining the old bundle until publication commits."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import shutil
import uuid
import unicodedata
import zipfile


def check_path(path):
    path = Path(os.path.abspath(path))
    for candidate in (path, *path.parents):
        if candidate.is_symlink():
            raise ValueError(f"Refusing symbolic-link installation path: {candidate}")
    return path


def bundle_info(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = info.get("CFBundleExecutable", "")
    if not info.get("CFBundleIdentifier") or not executable or Path(executable).name != executable:
        raise ValueError(f"Invalid application metadata: {app}")
    binary = app / "Contents/MacOS" / executable
    if not binary.is_file() or binary.is_symlink():
        raise ValueError(f"Invalid application executable: {binary}")
    return info, binary


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else _digest_stream(stream)


def _digest_stream(stream):
    result = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        result.update(block)
    return result.hexdigest()


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


def identity(path):
    stat = path.lstat()
    return stat.st_dev, stat.st_ino


def remove_owned(path, expected):
    if not path.exists() and not path.is_symlink():
        return
    if path.is_symlink() or identity(path) != expected:
        raise RuntimeError(f"Installation path changed; retaining it for recovery: {path}")
    shutil.rmtree(path)


class Installation:
    def __init__(self, target, previous, pending, helper, bundle_id, run):
        self.target = target
        self.previous = previous
        self.pending = pending
        self.helper = helper
        self.bundle_id = bundle_id
        self.run = run
        self.backup = None
        self.previous_identity = None
        self.pending_identity = None
        self.old_was_running = False
        self.swapped = False
        self.finished = False

    def lifecycle(self, action):
        return self.run([str(self.helper), action, str(self.target), self.bundle_id],
                        capture_output=True, text=True)

    def commit(self):
        if self.finished:
            return
        if self.previous_identity is not None and (self.backup is None or not self.backup.is_file()):
            raise RuntimeError("Verified rollback archive is missing; old application retained.")
        # Publication has committed. A cleanup error must not restore a partially
        # removed old bundle over the verified new application.
        self.finished = True
        if self.previous_identity is not None:
            remove_owned(self.previous, self.previous_identity)
        if self.pending_identity is not None:
            remove_owned(self.pending, self.pending_identity)
        self.finished = True

    def rollback(self):
        if self.finished:
            return
        if self.swapped:
            self.lifecycle("quit")
            remove_owned(self.target, self.pending_identity)
        if self.previous_identity is not None and self.previous.exists():
            if self.target.exists() or self.target.is_symlink():
                raise RuntimeError(f"Target changed; old application retained at {self.previous}")
            os.rename(self.previous, self.target)
            if self.old_was_running:
                self.lifecycle("launch")
        if self.pending_identity is not None:
            remove_owned(self.pending, self.pending_identity)
        self.finished = True


def install_app(source, target, work, run):
    source, target, work = check_path(source), check_path(target), check_path(work)
    if source == target or target in source.parents or source in target.parents:
        raise ValueError("Source and installation target must be separate directories.")
    source_info, source_binary = bundle_info(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    helper = work / "app_lifecycle"
    run(["xcrun", "swiftc", "-O", "-module-cache-path", str(work / "module-cache"),
         str(Path(__file__).with_name("app_lifecycle.swift")), "-o", str(helper)])
    token = uuid.uuid4().hex
    previous = target.with_name(f".MacOptimizer-previous-{token}.app")
    pending = target.with_name(f".MacOptimizer-pending-{token}.app")
    transaction = Installation(target, previous, pending, helper,
                               source_info["CFBundleIdentifier"], run)
    try:
        transaction.lifecycle("preflight")
        transaction.old_was_running = bool(json.loads(transaction.lifecycle("status").stdout))
        old_identity = None
        if target.exists():
            old_info, old_binary = bundle_info(target)
            if old_info["CFBundleIdentifier"] != source_info["CFBundleIdentifier"]:
                raise ValueError("Installed application has a different bundle identifier.")
            old_identity = identity(target)
            transaction.backup = work / "previous-install.zip"
            old_hash = digest(old_binary)
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(target), str(transaction.backup)])
            with zipfile.ZipFile(transaction.backup) as archive:
                if archive.testzip() is not None:
                    raise RuntimeError("Rollback archive checksum verification failed.")
                entry = f"{target.name}/Contents/MacOS/{old_info['CFBundleExecutable']}"
                if hashlib.sha256(archive.read(archive_entry(archive, entry))).hexdigest() != old_hash:
                    raise RuntimeError("Rollback archive executable mismatch.")
        pending.mkdir()
        transaction.pending_identity = identity(pending)
        run(["ditto", str(source), str(pending)])
        run(["codesign", "--verify", "--deep", "--strict", str(pending)])
        pending_info, pending_binary = bundle_info(pending)
        expected = (source_info.get("CFBundleIdentifier"), source_info.get("CFBundleShortVersionString"),
                    source_info.get("CFBundleVersion"))
        actual = tuple(pending_info.get(key) for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"))
        source_hash = digest(source_binary)
        if actual != expected or digest(pending_binary) != source_hash:
            raise RuntimeError("Staged installation metadata or executable mismatch.")
        transaction.lifecycle("quit")
        if old_identity is not None:
            if identity(target) != old_identity:
                raise RuntimeError("Installed application changed during installation.")
            os.rename(target, previous)
            transaction.previous_identity = old_identity
        elif target.exists() or target.is_symlink():
            raise RuntimeError("Installation target appeared during installation.")
        if pending.is_symlink() or identity(pending) != transaction.pending_identity:
            raise RuntimeError("Staged application changed during installation.")
        os.rename(pending, target)
        transaction.swapped = True
        run(["codesign", "--verify", "--deep", "--strict", str(target)])
        installed_info, installed_binary = bundle_info(target)
        if tuple(installed_info.get(key) for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion")) != expected or digest(installed_binary) != source_hash:
            raise RuntimeError("Installed application verification failed.")
        transaction.lifecycle("launch")
        return transaction
    except BaseException:
        transaction.rollback()
        raise
