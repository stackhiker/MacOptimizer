"""Packaging safety tests. All artifacts and tool outputs live in isolated fixtures."""
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock
import zipfile


REPOSITORY = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("build_package_under_test", REPOSITORY / "scripts/build_package.py")
package = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = package
SPEC.loader.exec_module(package)
APP = "Mac优化大师.app"
MANIFEST = ".macoptimizer-build-manifest.json"


class FakeTools:
    """Fake external tools only; exercise real packaging, publish, and pruning."""

    def __init__(self, failure=None, failure_arch=None, running_executables=()):
        self.failure = failure
        self.failure_arch = failure_arch
        self.calls = []
        self.arch = None
        self.running_executables = [str(path) for path in running_executables]

    def __call__(self, command, **kwargs):
        command = [str(value) for value in command]
        self.calls.append(command)
        if command == ["/bin/ps", "-axww", "-o", "comm="]:
            phase = "processes"
        elif command == ["xcrun", "--sdk", "macosx", "--show-sdk-path"]:
            phase = "sdk"
        elif command[:2] == ["xcrun", "swiftc"]:
            phase = "compile"
            self.arch = command[command.index("-target") + 1].split("-")[0]
        elif command[0] == "codesign":
            phase = "signature-verify" if "--verify" in command else "sign"
        elif command[:2] == ["lipo", "-verify_arch"]:
            phase = "architecture-verify"
        elif command[:2] == ["hdiutil", "create"]:
            phase = "dmg-create"
        elif command[:2] == ["hdiutil", "verify"]:
            phase = "dmg-verify"
        else:
            raise AssertionError(f"Unexpected external command: {command}")
        if phase == self.failure and (self.failure_arch is None or self.failure_arch == self.arch):
            raise subprocess.CalledProcessError(9, command, stderr="Permission denied" if phase == "dmg-create" else None)
        if phase == "compile":
            executable = Path(command[command.index("-o") + 1])
            executable.parent.mkdir(parents=True, exist_ok=True)
            info = plistlib.loads((executable.parent.parent / "Info.plist").read_bytes())
            executable.write_bytes(f"executable:{self.arch}:{info['CFBundleVersion']}".encode())
            executable.chmod(0o755)
        elif phase == "dmg-create":
            content = Path(command[command.index("-srcfolder") + 1])
            executable = content / APP / "Contents/MacOS/AppUninstaller"
            Path(command[-1]).write_bytes(b"dmg:" + executable.read_bytes())
        elif phase == "dmg-verify":
            if not Path(command[-1]).read_bytes().startswith(b"dmg:"):
                raise AssertionError("DMG verification must follow creation")
        elif phase in ("signature-verify", "sign"):
            if not (Path(command[-1]) / "Contents/MacOS/AppUninstaller").is_file():
                raise AssertionError("Signing must follow compilation")
        stdout = "/fixture SDK\n" if phase == "sdk" else ""
        if phase == "processes":
            stdout = "\n".join(self.running_executables)
        return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")


class BusyDMGTools(FakeTools):
    def __init__(self, fail_attempts, before_create, message="hdiutil: create failed - Resource busy"):
        super().__init__()
        self.fail_attempts = fail_attempts
        self.before_create = before_create
        self.message = message
        self.create_attempts = 0
        self.leftover_seen = []

    def __call__(self, command, **kwargs):
        values = [str(value) for value in command]
        if values[:2] == ["hdiutil", "create"]:
            self.create_attempts += 1
            self.before_create()
            target = Path(values[-1])
            self.leftover_seen.append(target.exists())
            if self.create_attempts <= self.fail_attempts:
                self.calls.append(values)
                target.write_bytes(b"incomplete current-run DMG")
                raise subprocess.CalledProcessError(16, values, output="", stderr=self.message)
        return super().__call__(command, **kwargs)


class BuildPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="MacOptimizer packaging tests ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / "repo with spaces"
        self.repo.mkdir()
        source = self.repo / "AppUninstaller"
        source.mkdir()
        (source / "Dummy.swift").write_text("// fixture only\n")
        (source / "icon.png").write_bytes(b"fixture resource")
        (source / "Localizations/en.lproj").mkdir(parents=True)
        (source / "Localizations/en.lproj/Localizable.strings").write_text('"fixture" = "fixture";\n')
        self.set_build("14")

    def metadata(self, version="5.0", build="14"):
        return {"CFBundleIdentifier": "com.tool.AppUninstaller", "CFBundleExecutable": "AppUninstaller",
                "CFBundleName": "Mac优化大师", "CFBundleShortVersionString": version, "CFBundleVersion": build}

    def set_build(self, build, version="5.0"):
        (self.repo / "AppUninstaller/Info.plist").write_bytes(plistlib.dumps(self.metadata(version, build)))

    def write_backup(self, path, build="12", bundle_id=None, include_binary=True):
        metadata = self.metadata(build=build)
        if bundle_id is not None:
            metadata["CFBundleIdentifier"] = bundle_id
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(APP + "/Contents/Info.plist", plistlib.dumps(metadata))
            if include_binary:
                archive.writestr(APP + "/Contents/MacOS/AppUninstaller", b"nonempty fixture binary")

    def invoke(self, args=(), tools=None):
        tools = tools or FakeTools()
        with mock.patch.object(package, "run", tools), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return package.main(list(args), repo_root=self.repo)

    def tree(self, directory):
        result = {}
        if not directory.exists():
            return result
        for entry in directory.rglob("*"):
            relative = str(entry.relative_to(directory))
            if entry.is_symlink():
                result[relative] = ("symlink", os.readlink(entry))
            elif entry.is_file():
                result[relative] = ("file", entry.read_bytes())
            elif entry.is_dir():
                result[relative] = ("directory",)
        return result

    def assert_no_private_work(self):
        for name in ("build", "build_release"):
            output = self.repo / name
            if output.is_dir() and not output.is_symlink():
                self.assertEqual(list(output.glob(".macoptimizer-package-*")), [])

    def legacy(self, output, version="5.0", build="12", valid=True):
        release = output / f"release-{version}-build{build}"
        app = release / APP
        (app / "Contents/MacOS").mkdir(parents=True)
        info = self.metadata(version, build)
        if not valid:
            info["CFBundleIdentifier"] = "org.unrelated.application"
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        (app / "Contents/MacOS/AppUninstaller").write_bytes(b"old executable")
        (release / f"MacOptimizer_v{version}_build{build}_AppleSilicon.dmg").write_bytes(b"old dmg")
        (release / "diagnostics.txt").write_text("keep diagnostics")
        return release

    def test_tool_failures_keep_published_outputs_and_history(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        self.legacy(output)
        before = self.tree(output)
        self.set_build("15")
        for phase in ("sdk", "compile", "sign", "signature-verify", "architecture-verify", "dmg-create", "dmg-verify", "processes"):
            with self.subTest(phase=phase):
                tools = FakeTools(failure=phase)
                self.assertNotEqual(self.invoke(tools=tools), 0)
                if phase == "dmg-create":
                    self.assertEqual(sum(call[:2] == ["hdiutil", "create"] for call in tools.calls), 1,
                                     "permission errors must not be retried")
                self.assertEqual(self.tree(output), before)
                self.assert_no_private_work()

    def test_transient_dmg_busy_retries_only_private_image_then_publishes(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        old_app = self.tree(output / APP)
        old_dmg = (output / "Mac优化大师.dmg").read_bytes()
        old_manifest = (output / MANIFEST).read_bytes()
        unknown = output / "unowned.dmg"
        unknown.write_bytes(b"unrelated image")

        def before_create():
            self.assertEqual(self.tree(output / APP), old_app)
            self.assertEqual((output / "Mac优化大师.dmg").read_bytes(), old_dmg)
            self.assertEqual((output / MANIFEST).read_bytes(), old_manifest)
            self.assertEqual(unknown.read_bytes(), b"unrelated image")

        self.set_build("15")
        tools = BusyDMGTools(1, before_create)
        with mock.patch.object(package.time, "sleep") as sleep:
            self.assertEqual(self.invoke(tools=tools), 0)
        self.assertEqual(tools.create_attempts, 2)
        self.assertEqual(tools.leftover_seen, [False, False], "retry must discard only its incomplete staged DMG")
        sleep.assert_called_once_with(1)
        self.assertEqual(sum(call[:2] == ["hdiutil", "verify"] for call in tools.calls), 1)
        self.assertEqual(plistlib.loads((output / APP / "Contents/Info.plist").read_bytes())["CFBundleVersion"], "15")
        self.assertNotEqual((output / "Mac优化大师.dmg").read_bytes(), old_dmg)
        self.assertEqual(unknown.read_bytes(), b"unrelated image")
        self.assert_no_private_work()

    def test_exhausted_dmg_busy_retries_preserve_old_artifacts_and_remove_private_work(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        self.legacy(output)
        before = self.tree(output)
        old_dmg = (output / "Mac优化大师.dmg").read_bytes()
        self.set_build("15")
        tools = BusyDMGTools(3, lambda: self.assertEqual((output / "Mac优化大师.dmg").read_bytes(), old_dmg),
                             message="hdiutil: create failed - 资源忙")
        with mock.patch.object(package.time, "sleep") as sleep:
            self.assertNotEqual(self.invoke(tools=tools), 0)
        self.assertEqual(tools.create_attempts, 3)
        self.assertEqual(tools.leftover_seen, [False, False, False])
        self.assertEqual(sleep.call_args_list, [mock.call(1), mock.call(2)])
        self.assertFalse(any(call[:2] == ["hdiutil", "verify"] for call in tools.calls))
        self.assertEqual(self.tree(output), before)
        self.assert_no_private_work()

    def test_running_published_app_prevents_replacement_and_history_cleanup(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        self.legacy(output)
        before = self.tree(output)
        self.set_build("15")
        running = output / APP / "Contents/MacOS/AppUninstaller"
        self.assertNotEqual(self.invoke(tools=FakeTools(running_executables=[running])), 0)
        self.assertEqual(self.tree(output), before)
        self.assert_no_private_work()

    def test_running_history_is_kept_and_unrelated_installed_app_does_not_block(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        active_legacy = self.legacy(output, build="12")
        idle_legacy = self.legacy(output, build="11")
        legacy_before = self.tree(active_legacy)
        managed_app = output / "x86_64" / APP
        shutil.copytree(output / APP, managed_app)
        managed_before = self.tree(managed_app)
        manifest = json.loads((output / MANIFEST).read_text())
        manifest["artifacts"].append({"path": "x86_64/" + APP, "kind": "app"})
        (output / MANIFEST).write_text(json.dumps(manifest))
        running = [active_legacy / APP / "Contents/MacOS/AppUninstaller",
                   managed_app / "Contents/MacOS/AppUninstaller",
                   Path("/Applications") / APP / "Contents/MacOS/AppUninstaller"]
        self.set_build("15")
        self.assertEqual(self.invoke(tools=FakeTools(running_executables=running)), 0)
        self.assertEqual(self.tree(active_legacy), legacy_before)
        self.assertEqual(self.tree(managed_app), managed_before)
        self.assertFalse((idle_legacy / APP).exists())
        self.assertFalse((idle_legacy / "MacOptimizer_v5.0_build11_AppleSilicon.dmg").exists())
        metadata = plistlib.loads((output / APP / "Contents/Info.plist").read_bytes())
        self.assertEqual(metadata["CFBundleVersion"], "15")
        self.assert_no_private_work()

    def test_second_architecture_failure_does_not_publish_first_architecture(self):
        self.assertEqual(self.invoke(["--arch", "both"]), 0)
        output = self.repo / "build_release"
        self.legacy(output)
        before = self.tree(output)
        self.set_build("15")
        tools = FakeTools(failure="compile", failure_arch="x86_64")
        self.assertNotEqual(self.invoke(["--arch", "both"], tools), 0)
        self.assertTrue(any(call[:2] == ["hdiutil", "verify"] for call in tools.calls))
        self.assertEqual(self.tree(output), before)
        self.assert_no_private_work()

    def test_success_retires_only_owned_and_identity_verified_artifacts(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        retired = output / "Mac优化大师_v4.0_Intel.dmg"
        retired.write_bytes(b"manifest-owned prior artifact")
        manifest = json.loads((output / MANIFEST).read_text())
        manifest["artifacts"].append({"path": retired.name, "kind": "dmg"})
        (output / MANIFEST).write_text(json.dumps(manifest))
        legacy = self.legacy(output)
        unrelated_release = self.legacy(output, build="11", valid=False)
        unrelated_before = self.tree(unrelated_release)
        backups = output / "backups"
        backups.mkdir()
        old_backup = backups / "MacOptimizer_v5.0_build12_before_build13_20261116T000000Z.zip"
        self.write_backup(old_backup)
        rollback = backups / "previous-install.zip"
        self.write_backup(rollback, build="14")
        rollback_bytes = rollback.read_bytes()
        sentinels = [output / "notes/source.swift", output / "personal-data.zip", backups / "my-notes.zip",
                     self.repo / ".build/shared-module-cache/keep", self.repo / "another-temp/source.swift"]
        for path in sentinels:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"unowned sentinel")
        self.set_build("15")
        self.assertEqual(self.invoke(), 0)
        self.assertFalse(retired.exists())
        self.assertFalse((legacy / APP).exists())
        self.assertFalse((legacy / "MacOptimizer_v5.0_build12_AppleSilicon.dmg").exists())
        self.assertEqual((legacy / "diagnostics.txt").read_text(), "keep diagnostics")
        self.assertFalse(old_backup.exists())
        self.assertEqual(self.tree(unrelated_release), unrelated_before)
        self.assertEqual(rollback.read_bytes(), rollback_bytes)
        for path in sentinels:
            self.assertEqual(path.read_bytes(), b"unowned sentinel")
        published = plistlib.loads((output / APP / "Contents/Info.plist").read_bytes())
        self.assertEqual(published["CFBundleVersion"], "15")
        self.assertEqual((output / APP / "Contents/Resources/icon.png").read_bytes(), b"fixture resource")
        self.assert_no_private_work()

    def test_old_backup_is_retained_until_a_valid_replacement_exists(self):
        self.assertEqual(self.invoke(), 0)
        backups = self.repo / "build/backups"
        backups.mkdir()
        old_backup = backups / "MacOptimizer_v5.0_build12_before_build13_20261116T000000Z.zip"
        self.write_backup(old_backup)
        before = old_backup.read_bytes()
        replacement = backups / "previous-install.zip"
        for state in ("absent", "corrupt", "wrong-bundle", "info-only"):
            with self.subTest(replacement=state):
                if replacement.exists():
                    replacement.unlink()
                if state == "corrupt":
                    replacement.write_bytes(b"invalid ZIP")
                elif state == "wrong-bundle":
                    self.write_backup(replacement, bundle_id="org.unrelated.app")
                elif state == "info-only":
                    self.write_backup(replacement, include_binary=False)
                self.assertEqual(self.invoke(), 0)
                self.assertEqual(old_backup.read_bytes(), before)
                self.assert_no_private_work()
        self.write_backup(replacement, build="14")
        self.assertEqual(self.invoke(), 0)
        self.assertFalse(old_backup.exists())
        self.assertTrue(replacement.is_file())

    @unittest.skipUnless(Path("/usr/bin/ditto").is_file(), "macOS ditto is required for its native ZIP encoding")
    def test_native_ditto_chinese_backups_require_a_crc_valid_replacement(self):
        output = self.repo / "build"
        backups = output / "backups"
        backups.mkdir(parents=True)
        fixture = self.root / "native archive fixture" / APP
        (fixture / "Contents/MacOS").mkdir(parents=True)
        info = fixture / "Contents/Info.plist"
        info.write_bytes(plistlib.dumps(self.metadata(build="12")))
        binary = fixture / "Contents/MacOS/AppUninstaller"
        binary.write_bytes(b"#!/bin/sh\nexit 0\n")
        binary.chmod(0o755)
        old_backup = backups / "MacOptimizer_v5.0_build12_before_build13_20261116T000000Z.zip"

        def native_archive(destination):
            subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                            str(fixture), str(destination)], check=True, capture_output=True, timeout=10)

        native_archive(old_backup)
        old_bytes = old_backup.read_bytes()
        self.assertEqual(self.invoke(), 0)
        self.assertEqual(old_backup.read_bytes(), old_bytes)

        info.write_bytes(plistlib.dumps(self.metadata(build="14")))
        healthy = self.root / "healthy-native.zip"
        native_archive(healthy)
        with zipfile.ZipFile(healthy) as archive:
            self.assertIsNone(archive.testzip())
        healthy_bytes = healthy.read_bytes()
        # ditto can write UTF-8 filename bytes without setting ZIP's UTF-8 flag.
        # Damage only the fixture binary's central CRC, leaving metadata readable.
        damaged = bytearray(healthy_bytes)
        expected_name = (APP + "/Contents/MacOS/AppUninstaller").encode("utf-8")
        offset = 0
        changed = False
        while True:
            offset = damaged.find(b"PK\x01\x02", offset)
            if offset < 0:
                break
            name_length = struct.unpack_from("<H", damaged, offset + 28)[0]
            name = bytes(damaged[offset + 46:offset + 46 + name_length])
            if name == expected_name:
                crc = struct.unpack_from("<I", damaged, offset + 16)[0]
                struct.pack_into("<I", damaged, offset + 16, crc ^ 1)
                changed = True
                break
            offset += 4
        self.assertTrue(changed, "native archive must contain the Chinese app binary")
        replacement = backups / "previous-install.zip"
        replacement.write_bytes(damaged)
        with zipfile.ZipFile(replacement) as archive:
            self.assertIsNotNone(archive.testzip())
        self.assertEqual(self.invoke(), 0)
        self.assertEqual(old_backup.read_bytes(), old_bytes)

        replacement.write_bytes(healthy_bytes)
        self.assertEqual(self.invoke(), 0)
        self.assertFalse(old_backup.exists(), "a verified native rollback enables retirement of native historical ZIPs")
        self.assertEqual(replacement.read_bytes(), healthy_bytes)
        self.assert_no_private_work()

    def test_unmanifested_dual_outputs_retire_only_metadata_matched_old_dmgs(self):
        output = self.repo / "build_release"
        expected_old = []
        for arch, label in (("arm64", "AppleSilicon"), ("x86_64", "Intel")):
            app = output / arch / APP
            (app / "Contents/MacOS").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.metadata(version="4.0", build="12")))
            (app / "Contents/MacOS/AppUninstaller").write_bytes(b"previous native build")
            dmg = output / f"Mac优化大师_v4.0_{label}.dmg"
            dmg.write_bytes(b"old corresponding DMG")
            expected_old.append(dmg)
        unknown = [output / "personal-notes.dmg", output / "Mac优化大师_v3.0_Intel.dmg",
                   output / "Mac优化大师_v4.0_custom.dmg"]
        for path in unknown:
            path.write_bytes(b"unowned disk image")
        self.assertFalse((output / MANIFEST).exists())
        before = self.tree(output)
        self.assertNotEqual(self.invoke(["--arch", "both"], FakeTools(failure="compile", failure_arch="x86_64")), 0)
        self.assertEqual(self.tree(output), before, "migration cleanup must wait for all architectures to succeed")
        self.assertEqual(self.invoke(["--arch", "both"]), 0)
        for path in expected_old:
            self.assertFalse(path.exists())
        for path in unknown:
            self.assertEqual(path.read_bytes(), b"unowned disk image")
        for arch, label in (("arm64", "AppleSilicon"), ("x86_64", "Intel")):
            metadata = plistlib.loads((output / arch / APP / "Contents/Info.plist").read_bytes())
            self.assertEqual(metadata["CFBundleVersion"], "14")
            self.assertTrue((output / f"Mac优化大师_v5.0_{label}.dmg").is_file())
        self.assert_no_private_work()

    def test_output_root_symlink_is_rejected_without_following_it(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "keep").write_text("untouched")
        (self.repo / "build").symlink_to(outside, target_is_directory=True)
        tools = FakeTools()
        self.assertNotEqual(self.invoke(tools=tools), 0)
        self.assertEqual(tools.calls, [])
        self.assertTrue((self.repo / "build").is_symlink())
        self.assertEqual(self.tree(outside), {"keep": ("file", b"untouched")})

    def test_retired_symlink_candidate_does_not_delete_its_target(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        outside = self.root / "outside.dmg"
        outside.write_bytes(b"outside must survive")
        link = output / "Mac优化大师_v4.0_Intel.dmg"
        link.symlink_to(outside)
        manifest = json.loads((output / MANIFEST).read_text())
        manifest["artifacts"].append({"path": link.name, "kind": "dmg"})
        (output / MANIFEST).write_text(json.dumps(manifest))
        self.set_build("15")
        self.invoke()
        self.assertTrue(link.is_symlink())
        self.assertEqual(outside.read_bytes(), b"outside must survive")
        self.assert_no_private_work()

    def test_current_app_symlink_is_not_replaced_or_followed(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        outside = self.root / "external.app"
        (output / APP).rename(outside)
        (output / APP).symlink_to(outside, target_is_directory=True)
        before = self.tree(output)
        external_before = self.tree(outside)
        self.set_build("15")
        self.assertNotEqual(self.invoke(), 0)
        self.assertEqual(self.tree(output), before)
        self.assertEqual(self.tree(outside), external_before)
        self.assert_no_private_work()

    def test_legacy_symlink_and_unknown_directory_are_preserved(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        outside = self.root / "outside-history"
        outside.mkdir()
        external_release = self.legacy(outside)
        (output / external_release.name).symlink_to(external_release, target_is_directory=True)
        unknown = output / "release-personal-notes-build12"
        unknown.mkdir()
        (unknown / "source.swift").write_text("keep source")
        external_before = self.tree(outside)
        self.assertEqual(self.invoke(), 0)
        self.assertTrue((output / external_release.name).is_symlink())
        self.assertEqual(self.tree(outside), external_before)
        self.assertEqual((unknown / "source.swift").read_text(), "keep source")
        self.assert_no_private_work()

    def test_manifest_path_traversal_fails_before_build_or_cleanup(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        sentinel = self.repo / ".build/keep"
        sentinel.write_bytes(b"keep")
        manifest = json.loads((output / MANIFEST).read_text())
        manifest["artifacts"].append({"path": "../.build/keep", "kind": "dmg"})
        (output / MANIFEST).write_text(json.dumps(manifest))
        before = self.tree(output)
        tools = FakeTools()
        self.assertNotEqual(self.invoke(tools=tools), 0)
        self.assertEqual(tools.calls, [])
        self.assertEqual(self.tree(output), before)
        self.assertEqual(sentinel.read_bytes(), b"keep")

    def test_publish_failure_restores_previous_manifest_and_outputs(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        self.legacy(output)
        before = self.tree(output)
        self.set_build("15")
        replace = os.replace
        injected = []

        def fail_once(source, target):
            if Path(target) == output / "Mac优化大师.dmg" and not injected:
                injected.append(True)
                raise OSError("fixture publication failure")
            return replace(source, target)

        with mock.patch.object(package.os, "replace", side_effect=fail_once):
            self.assertNotEqual(self.invoke(), 0)
        self.assertEqual(injected, [True])
        self.assertEqual(self.tree(output), before)
        self.assert_no_private_work()

    def test_failed_rollback_keeps_old_artifacts_in_a_recoverable_directory(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        executable_relative = Path(APP) / "Contents/MacOS/AppUninstaller"
        old_executable = (output / executable_relative).read_bytes()
        old_dmg = (output / "Mac优化大师.dmg").read_bytes()
        old_manifest = (output / MANIFEST).read_bytes()
        unknown = output / "unowned/source.swift"
        unknown.parent.mkdir()
        unknown.write_bytes(b"preserve unknown")
        self.set_build("15")
        replace = os.replace
        faults = []

        def fail_publication_and_app_restore(source, target):
            source, target = Path(source), Path(target)
            if target == output / "Mac优化大师.dmg" and "publish" not in faults:
                faults.append("publish")
                raise OSError("fixture publication failure")
            if target == output / APP and "publish" in faults and "restore" not in faults:
                faults.append("restore")
                raise OSError("fixture recovery failure")
            return replace(source, target)

        with mock.patch.object(package.os, "replace", side_effect=fail_publication_and_app_restore):
            self.assertNotEqual(self.invoke(), 0)
        self.assertEqual(faults, ["publish", "restore"])
        recoveries = [path for path in output.iterdir() if path.name.startswith(".macoptimizer-recovery-")]
        self.assertEqual(len(recoveries), 1, "the old app must survive automatic temporary cleanup")
        self.assertEqual((recoveries[0] / executable_relative).read_bytes(), old_executable)
        self.assertFalse((output / APP).exists(), "failed publication must not expose a partial new app")
        self.assertEqual((output / "Mac优化大师.dmg").read_bytes(), old_dmg)
        self.assertEqual((output / MANIFEST).read_bytes(), old_manifest)
        self.assertEqual(unknown.read_bytes(), b"preserve unknown")
        self.assert_no_private_work()

    def test_install_transaction_rolls_back_if_publication_fails(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        before = self.tree(output)
        transaction = types.SimpleNamespace(backup=None, commit=mock.Mock(), rollback=mock.Mock())
        install = mock.Mock(return_value=transaction)
        fake_module = types.SimpleNamespace(install_app=install)
        with mock.patch.dict(sys.modules, {"install_built_app": fake_module}), \
                mock.patch.object(package.platform, "machine", return_value="arm64"), \
                mock.patch.object(package, "publish", side_effect=OSError("fixture publish failure")):
            self.assertNotEqual(self.invoke(["--install", "--install-dir", str(self.root / "Applications")]), 0)
        install.assert_called_once()
        transaction.rollback.assert_called_once_with()
        transaction.commit.assert_not_called()
        self.assertEqual(self.tree(output), before)
        self.assert_no_private_work()

    def test_install_commit_precedes_old_artifact_cleanup(self):
        self.assertEqual(self.invoke(), 0)
        output = self.repo / "build"
        legacy = self.legacy(output)
        observations = []

        def install(source, target, work, runner):
            backup = work / "installation-rollback.zip"
            backup.write_bytes(b"verified install rollback")
            transaction = types.SimpleNamespace(backup=backup, rollback=mock.Mock())

            def commit():
                observations.append(((legacy / APP).is_dir(), transaction.backup.read_bytes(),
                                     transaction.backup == output / "backups/previous-install.zip"))

            transaction.commit = commit
            return transaction

        with mock.patch.dict(sys.modules, {"install_built_app": types.SimpleNamespace(install_app=install)}), \
                mock.patch.object(package.platform, "machine", return_value="arm64"):
            self.assertEqual(self.invoke(["--install", "--install-dir", str(self.root / "Applications")]), 0)
        self.assertEqual(observations, [(True, b"verified install rollback", True)])
        self.assertFalse((legacy / APP).exists())
        self.assert_no_private_work()

    def test_second_process_is_refused_while_packaging_lock_is_held(self):
        lock = self.repo / ".build/packaging.lock"
        lock.parent.mkdir()
        holder_code = "import fcntl,sys; f=open(sys.argv[1], 'w'); fcntl.flock(f, fcntl.LOCK_EX); print('ready', flush=True); sys.stdin.read(1)"
        holder = subprocess.Popen([sys.executable, "-c", holder_code, str(lock)], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertTrue(select.select([holder.stdout], [], [], 5)[0], "lock holder did not start")
            self.assertEqual(holder.stdout.readline().strip(), "ready")
            inode = lock.stat().st_ino
            tools = FakeTools()
            self.assertNotEqual(self.invoke(tools=tools), 0)
            self.assertEqual(tools.calls, [])
            self.assertEqual(lock.stat().st_ino, inode)
            self.assertFalse((self.repo / "build").exists())
        finally:
            holder.communicate("x", timeout=5)
        self.assertEqual(holder.returncode, 0)

    def test_wrappers_resolve_their_own_repository_from_an_unrelated_cwd(self):
        scripts = self.repo / "scripts"
        scripts.mkdir()
        (scripts / "build_package.py").write_text("import json,os,sys; print(json.dumps({'argv':sys.argv[1:], 'script':__file__, 'cwd':os.getcwd()}))\n")
        for wrapper in ("build.sh", "build_dual_dmg.sh", "release_package.sh"):
            shutil.copy2(REPOSITORY / wrapper, self.repo / wrapper)
        outside = self.root / "outside caller"
        outside.mkdir()
        for wrapper, prefix in (("build.sh", []), ("build_dual_dmg.sh", ["--arch", "both"]),
                                ("release_package.sh", ["--arch", "both"])):
            with self.subTest(wrapper=wrapper):
                arguments = ["--install", "--install-dir", str(self.root / "Applications with spaces")]
                result = subprocess.run(["/bin/bash", str(self.repo / wrapper), *arguments], cwd=outside,
                                        check=True, capture_output=True, text=True, timeout=10)
                value = json.loads(result.stdout)
                self.assertEqual(Path(value["script"]), scripts / "build_package.py")
                self.assertEqual(value["argv"], prefix + arguments)
        self.assertEqual(list(outside.iterdir()), [])

    def test_help_does_not_create_lock_outputs_or_run_tools(self):
        before = self.tree(self.repo)
        tools = FakeTools()
        with self.assertRaises(SystemExit) as exit_context:
            self.invoke(["--help"], tools)
        self.assertEqual(exit_context.exception.code, 0)
        self.assertEqual(tools.calls, [])
        self.assertEqual(self.tree(self.repo), before)


if __name__ == "__main__":
    unittest.main()
