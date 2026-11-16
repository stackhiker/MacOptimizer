"""Real filesystem transaction fixtures; only platform commands are faked in unit tests.

Run unit tests with:
    python3 Tests/BuildScripts/test_install_built_app.py InstallationTransactionTests -v
Discovery includes the native fixture on macOS.
Run the real macOS integration fixture separately with:
    python3 Tests/BuildScripts/test_install_built_app.py NativeInstallationTests -v
"""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
import zipfile

REPOSITORY = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("install_built_app_under_test", REPOSITORY / "scripts/install_built_app.py")
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)


def make_bundle(path, version="1", payload=b"fixture-old", bundle_id="dev.macoptimizer.fixture.unit"):
    (path / "Contents/MacOS").mkdir(parents=True)
    info = {"CFBundleIdentifier": bundle_id, "CFBundleExecutable": "Fixture", "CFBundleName": "Installer Fixture",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0", "CFBundleVersion": version,
            "LSUIElement": True, "NSHighResolutionCapable": True}
    (path / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    binary = path / "Contents/MacOS/Fixture"
    binary.write_bytes(payload)
    binary.chmod(0o755)
    (path / "Contents/Resources").mkdir()
    (path / "Contents/Resources/retained.txt").write_text("fixture resource")
    return path


class LegacyUTF8ZipInfo(zipfile.ZipInfo):
    """Reproduce local ditto's UTF-8 name bytes without ZIP's UTF-8 flag."""
    def _encodeFilenameFlags(self):
        return self.filename.encode("utf-8"), self.flag_bits & ~0x800


class FilesystemRunner:
    """Mock platform commands but perform every copy/archive mutation on real files."""
    def __init__(self, *, running=False, failure=None, archive_mode=None, after_copy=None, on_quit=None):
        self.running = running
        self.failure = failure
        self.archive_mode = archive_mode
        self.after_copy = after_copy
        self.on_quit = on_quit
        self.calls = []
        self.launches = []
        self.failed_launch = False

    @staticmethod
    def fail(args):
        raise subprocess.CalledProcessError(1, args, stderr="injected platform failure")

    def __call__(self, args, **kwargs):
        args = [str(arg) for arg in args]
        self.calls.append(args)
        command = Path(args[0]).name
        stdout = ""
        if command == "xcrun":
            Path(args[args.index("-o") + 1]).write_text("fixture lifecycle helper")
        elif command == "ditto" and "-c" in args:
            source, destination = Path(args[-2]), Path(args[-1])
            if self.archive_mode == "invalid":
                destination.write_bytes(b"not a zip")
            else:
                with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
                    for file in source.rglob("*"):
                        if file.is_file():
                            entry = str(Path(source.name) / file.relative_to(source))
                            data = file.read_bytes()
                            if self.archive_mode == "wrong_executable" and "/MacOS/" in entry:
                                data = b"wrong old executable"
                            info = LegacyUTF8ZipInfo(entry) if self.archive_mode == "legacy_utf8_filename" else entry
                            archive.writestr(info, data)
        elif command == "ditto":
            source, destination = Path(args[-2]), Path(args[-1])
            if self.failure == "copy":
                (destination / "partial-copy").write_text("partial")
                self.fail(args)
            shutil.copytree(source, destination, dirs_exist_ok=True)
            if self.after_copy:
                self.after_copy(destination)
        elif command == "codesign":
            candidate = Path(args[-1])
            phase = "candidate_signature" if candidate.name.startswith(".MacOptimizer-pending-") else "installed_signature"
            if self.failure == phase:
                self.fail(args)
        elif command == "app_lifecycle":
            action, target = args[1], Path(args[2])
            if action == "status":
                stdout = json.dumps([12345] if self.running else [])
            elif action == "quit":
                self.running = False
                if self.on_quit:
                    callback, self.on_quit = self.on_quit, None
                    callback(target)
            elif action == "launch":
                version = INSTALLER.bundle_info(target)[0]["CFBundleVersion"]
                self.launches.append(version)
                if self.failure == "launch" and not self.failed_launch:
                    self.failed_launch = True
                    self.fail(args)
                self.running = True
            elif action != "preflight":
                raise AssertionError(f"Unexpected lifecycle action: {args}")
        else:
            raise AssertionError(f"Unexpected platform command: {args}")
        return subprocess.CompletedProcess(args, 0, stdout=stdout, stderr="")


class InstallationTransactionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="macoptimizer-install-unit-", dir="/private/tmp" if sys.platform == "darwin" else None)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = make_bundle(self.root / "Source.app", "2", b"fixture-new")
        self.applications = self.root / "Applications"
        self.applications.mkdir()
        self.target = make_bundle(self.applications / "Fixture.app")
        self.work = self.root / "work"
        self.work.mkdir()
        self.old_identity = INSTALLER.identity(self.target)

    def install(self, runner):
        return INSTALLER.install_app(self.source, self.target, self.work, runner)

    def assert_old_preserved(self):
        self.assertEqual(INSTALLER.identity(self.target), self.old_identity)
        self.assertEqual((self.target / "Contents/MacOS/Fixture").read_bytes(), b"fixture-old")

    def assert_no_transaction_directories(self):
        self.assertFalse(list(self.applications.glob(".MacOptimizer-pending-*.app")))
        self.assertFalse(list(self.applications.glob(".MacOptimizer-previous-*.app")))

    def test_partial_copy_failure_removes_owned_pending_preserves_old(self):
        runner = FilesystemRunner(running=True, failure="copy")
        with self.assertRaises(subprocess.CalledProcessError):
            self.install(runner)
        self.assert_old_preserved()
        self.assert_no_transaction_directories()
        self.assertTrue(runner.running)

    def test_candidate_signature_failure_preserves_old(self):
        runner = FilesystemRunner(running=True, failure="candidate_signature")
        with self.assertRaises(subprocess.CalledProcessError):
            self.install(runner)
        self.assert_old_preserved()
        self.assert_no_transaction_directories()
        self.assertTrue(runner.running)

    def test_installed_signature_failure_restores_old_and_restarts_it(self):
        runner = FilesystemRunner(running=True, failure="installed_signature")
        with self.assertRaises(subprocess.CalledProcessError):
            self.install(runner)
        self.assert_old_preserved()
        self.assert_no_transaction_directories()
        self.assertEqual(runner.launches, ["1"])
        self.assertTrue(runner.running)

    def test_launch_failure_restores_old_application(self):
        runner = FilesystemRunner(running=True, failure="launch")
        with self.assertRaises(subprocess.CalledProcessError):
            self.install(runner)
        self.assert_old_preserved()
        self.assert_no_transaction_directories()
        self.assertEqual(runner.launches, ["2", "1"])
        self.assertTrue(runner.running)

    def test_explicit_rollback_before_publication_restores_old(self):
        runner = FilesystemRunner(running=True)
        transaction = self.install(runner)
        self.assertEqual(INSTALLER.bundle_info(self.target)[0]["CFBundleVersion"], "2")
        self.assertTrue(transaction.previous.is_dir())
        transaction.rollback()
        transaction.rollback()  # Transaction completion is idempotent.
        self.assert_old_preserved()
        self.assert_no_transaction_directories()
        self.assertEqual(runner.launches, ["2", "1"])

    def test_commit_removes_only_owned_previous_and_pending_preserves_target(self):
        foreign = self.applications / ".MacOptimizer-previous-foreign.app"
        foreign.mkdir()
        (foreign / "sentinel").write_text("unrelated")
        transaction = self.install(FilesystemRunner())
        new_identity = INSTALLER.identity(self.target)
        transaction.commit()
        transaction.commit()
        self.assertEqual(INSTALLER.identity(self.target), new_identity)
        self.assertEqual((self.target / "Contents/MacOS/Fixture").read_bytes(), b"fixture-new")
        self.assertFalse(transaction.previous.exists())
        self.assertFalse(transaction.pending.exists())
        self.assertEqual((foreign / "sentinel").read_text(), "unrelated")
        self.assertTrue(transaction.backup.is_file())
        transaction.rollback()
        self.assertEqual(INSTALLER.identity(self.target), new_identity)

    def test_verified_old_archive_contains_original_executable(self):
        transaction = self.install(FilesystemRunner())
        with zipfile.ZipFile(transaction.backup) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(archive.read("Fixture.app/Contents/MacOS/Fixture"), b"fixture-old")
            self.assertEqual(archive.read("Fixture.app/Contents/Resources/retained.txt"), b"fixture resource")
        transaction.rollback()

    def test_ditto_legacy_utf8_chinese_archive_is_verified_and_can_rollback(self):
        renamed = self.target.with_name("Fixture 测试.app")
        os.rename(self.target, renamed)
        self.target = renamed
        transaction = self.install(FilesystemRunner(archive_mode="legacy_utf8_filename"))
        with zipfile.ZipFile(transaction.backup) as archive:
            executable_entries = [x for x in archive.infolist() if x.filename.endswith("/Contents/MacOS/Fixture")]
            self.assertEqual(len(executable_entries), 1)
            self.assertEqual(executable_entries[0].flag_bits & 0x800, 0)
            self.assertNotEqual(executable_entries[0].filename, "Fixture 测试.app/Contents/MacOS/Fixture")
            self.assertEqual(archive.read(executable_entries[0]), b"fixture-old")
        transaction.rollback()
        self.assert_old_preserved()
        self.assert_no_transaction_directories()

    def test_invalid_or_mismatched_archive_stops_before_replacement(self):
        for mode in ["invalid", "wrong_executable"]:
            with self.subTest(mode=mode):
                with self.assertRaises((zipfile.BadZipFile, RuntimeError)):
                    self.install(FilesystemRunner(archive_mode=mode))
                self.assert_old_preserved()
                self.assert_no_transaction_directories()

    def test_first_install_failures_leave_no_target_or_transaction_directories(self):
        shutil.rmtree(self.target)
        for failure in ["copy", "candidate_signature", "installed_signature", "launch"]:
            with self.subTest(failure=failure):
                with self.assertRaises(subprocess.CalledProcessError):
                    self.install(FilesystemRunner(failure=failure))
                self.assertFalse(self.target.exists())
                self.assert_no_transaction_directories()

    def test_initial_target_symlink_is_rejected_without_touching_destination(self):
        saved = self.root / "Saved.app"
        os.rename(self.target, saved)
        self.target.symlink_to(saved, target_is_directory=True)
        runner = FilesystemRunner()
        with self.assertRaises(ValueError):
            self.install(runner)
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(INSTALLER.identity(saved), self.old_identity)
        self.assertEqual(runner.calls, [])

    def test_target_identity_change_during_install_is_rejected(self):
        saved = self.root / "OriginalMoved.app"
        def replace(target):
            os.rename(target, saved)
            make_bundle(target, "99", b"foreign-target")
        with self.assertRaises(RuntimeError):
            self.install(FilesystemRunner(on_quit=replace))
        self.assertEqual(INSTALLER.identity(saved), self.old_identity)
        self.assertEqual((self.target / "Contents/MacOS/Fixture").read_bytes(), b"foreign-target")
        self.assert_no_transaction_directories()

    def test_rollback_rejects_changed_target_and_retains_old_for_recovery(self):
        transaction = self.install(FilesystemRunner())
        displaced = self.root / "DisplacedNew.app"
        os.rename(self.target, displaced)
        foreign = make_bundle(self.root / "Foreign.app", "99", b"foreign")
        self.target.symlink_to(foreign, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            transaction.rollback()
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(INSTALLER.identity(transaction.previous), self.old_identity)
        self.assertEqual((foreign / "Contents/MacOS/Fixture").read_bytes(), b"foreign")

    def test_commit_rejects_replaced_previous_and_never_rolls_back_new_target(self):
        transaction = self.install(FilesystemRunner())
        saved = self.root / "SavedPrevious.app"
        os.rename(transaction.previous, saved)
        transaction.previous.mkdir()
        (transaction.previous / "foreign").write_text("keep")
        target_identity = INSTALLER.identity(self.target)
        with self.assertRaises(RuntimeError):
            transaction.commit()
        transaction.rollback()
        self.assertEqual(INSTALLER.identity(self.target), target_identity)
        self.assertEqual((transaction.previous / "foreign").read_text(), "keep")
        self.assertEqual(INSTALLER.identity(saved), self.old_identity)

    def test_pending_symlink_replacement_is_rejected_before_old_app_swap(self):
        saved_pending = self.root / "DisplacedPending.app"
        alternate = make_bundle(self.root / "Alternate.app", "2", b"fixture-new")
        pending_paths = []
        def replace(pending):
            pending_paths.append(pending)
            os.rename(pending, saved_pending)
            pending.symlink_to(alternate, target_is_directory=True)
        with self.assertRaises((RuntimeError, ValueError)):
            self.install(FilesystemRunner(after_copy=replace))
        self.assert_old_preserved()
        self.assertTrue(pending_paths[0].is_symlink())
        self.assertEqual(pending_paths[0].resolve(), alternate)
        self.assertTrue(saved_pending.is_dir())
        self.assertEqual((alternate / "Contents/MacOS/Fixture").read_bytes(), b"fixture-new")


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS AppKit, codesign, and ditto")
class NativeInstallationTests(unittest.TestCase):
    """Real unsigned-development macOS lifecycle; unique app identity, temporary Apps only."""
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="macoptimizer-install-native-", dir="/private/tmp")
        cls.root = Path(cls.temporary.name).resolve()
        cls.work = cls.root / "work"
        cls.work.mkdir()
        cls.bundle_id = "dev.macoptimizer.installfixture." + uuid.uuid4().hex
        cls.target = cls.root / "Applications" / "Fixture 测试.app"
        cls.source = cls.root / "Incoming.app"
        cls.log_path = REPOSITORY / "Validation/BuildScripts/native-installation.log"
        cls.log_path.parent.mkdir(parents=True, exist_ok=True)
        cls.log = cls.log_path.open("w")
        cls.program = cls.root / "Fixture.swift"
        cls.program.write_text("import AppKit\nlet app = NSApplication.shared\napp.setActivationPolicy(.accessory)\napp.run()\n")
        try:
            cls.run_real(["xcrun", "swiftc", "-O", "-module-cache-path", str(cls.work / "module-cache"), str(cls.program), "-o", str(cls.root / "FixtureBinary")])
            cls.run_real(["xcrun", "swiftc", "-O", "-module-cache-path", str(cls.work / "module-cache"), str(REPOSITORY / "scripts/app_lifecycle.swift"), "-o", str(cls.work / "app_lifecycle")])
        except BaseException:
            cls.log.close()
            cls.temporary.cleanup()
            raise

    @classmethod
    def run_real(cls, args, **kwargs):
        kwargs.setdefault("capture_output", True)
        kwargs.setdefault("text", True)
        kwargs.setdefault("check", True)
        kwargs.setdefault("timeout", 120)
        cls.log.write(json.dumps([str(x) for x in args], ensure_ascii=False) + "\n")
        cls.log.flush()
        try:
            result = subprocess.run(args, **kwargs)
        except subprocess.CalledProcessError as error:
            cls.log.write(f"exit={error.returncode}\n")
            cls.log.write((error.stdout or "") + (error.stderr or ""))
            cls.log.flush()
            raise
        cls.log.write((result.stdout or "") + (result.stderr or ""))
        cls.log.flush()
        return result

    @classmethod
    def lifecycle(cls, action):
        return cls.run_real([str(cls.work / "app_lifecycle"), action, str(cls.target), cls.bundle_id])

    @classmethod
    def tearDownClass(cls):
        try:
            cls.lifecycle("quit")
            remaining = json.loads(cls.lifecycle("status").stdout)
            if remaining:
                raise AssertionError(f"Own fixture app still running: {remaining}")
        finally:
            cls.log.close()
            cls.temporary.cleanup()

    def signed_bundle(self, path, version):
        make_bundle(path, version, (self.root / "FixtureBinary").read_bytes(), self.bundle_id)
        self.run_real(["codesign", "--force", "--sign", "-", str(path)])
        self.run_real(["codesign", "--verify", "--deep", "--strict", str(path)])

    def test_actual_install_launch_rollback_then_commit(self):
        self.signed_bundle(self.target, "1")
        self.signed_bundle(self.source, "2")
        old_identity = INSTALLER.identity(self.target)
        self.lifecycle("launch")
        self.assertTrue(json.loads(self.lifecycle("status").stdout))
        first = INSTALLER.install_app(self.source, self.target, self.work, self.run_real)
        self.assertTrue(json.loads(self.lifecycle("status").stdout))
        self.assertEqual(INSTALLER.bundle_info(self.target)[0]["CFBundleVersion"], "2")
        first.rollback()
        self.assertEqual(INSTALLER.identity(self.target), old_identity)
        self.assertEqual(INSTALLER.bundle_info(self.target)[0]["CFBundleVersion"], "1")
        self.assertTrue(json.loads(self.lifecycle("status").stdout))
        second = INSTALLER.install_app(self.source, self.target, self.work, self.run_real)
        installed_identity = INSTALLER.identity(self.target)
        second.commit()
        self.assertEqual(INSTALLER.identity(self.target), installed_identity)
        self.assertTrue(json.loads(self.lifecycle("status").stdout))
        self.assertFalse(second.previous.exists())
        self.assertFalse(second.pending.exists())
        self.assertTrue(second.backup.is_file())
        self.run_real(["codesign", "--verify", "--deep", "--strict", str(self.target)])
        self.lifecycle("quit")
        self.assertEqual(json.loads(self.lifecycle("status").stdout), [])


if __name__ == "__main__":
    unittest.main()
