#!/usr/bin/env python3
from pathlib import Path
import plistlib, subprocess, sys, tempfile

scheme = sys.argv[1]
assert scheme in ("rootless", "rootful", "jailed"), "unknown scheme"
if scheme == "jailed":
    debs = [Path("packages/jailed/gotohp-tweak-jailed.deb")]
else:
    arch = "iphoneos-arm64" if scheme == "rootless" else "iphoneos-arm"
    debs = list(Path("packages").glob("*_" + arch + ".deb"))
assert debs, "no packages"
deb = max(debs, key=lambda p: p.stat().st_mtime)
prefix = "var/jb/" if scheme == "rootless" else ""


def verify_backup_integration(binary):
    # Prevent packaging a build with the original jailed-only source omissions.
    symbols = subprocess.check_output(["nm", "-gU", str(binary)], text=True)
    for function in (
        "GSStartBackupIntegration",
        "GSInstallBackupRequests",
        "GSInstallPhotosIntegration",
        "GSSetUploadHostForeground",
        "GSUploadMonitorSnapshot",
        "GSStartBatchImport",
        "GSBatchImportSnapshot",
        "GSPhotoIdentifierProvider",
    ):
        assert "_" + function in symbols, f"{binary}: missing {function}"


with tempfile.TemporaryDirectory() as d:
    subprocess.run(["dpkg-deb", "-x", str(deb), d], check=True)
    if scheme == "jailed":
        r = Path(d)
        binary = r / "Library/MobileSubstrate/DynamicLibraries/GunshotJailed.dylib"
        assert binary.is_file()
        verify_backup_integration(binary)
        assert (
            binary.read_bytes()
            == Path("packages/jailed/GunshotJailed.dylib").read_bytes()
        )
        assert sorted(str(p.relative_to(r)) for p in r.rglob("*") if p.is_file()) == [
            "Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            "Library/Frameworks/CydiaSubstrate.framework/Info.plist",
            "Library/Frameworks/CydiaSubstrate.framework/_CodeSignature/CodeResources",
            "Library/MobileSubstrate/DynamicLibraries/GunshotJailed.dylib",
            "Library/MobileSubstrate/DynamicLibraries/GunshotJailed.plist",
            "usr/share/doc/dev.tqmane.gunshot.jailed/ThirdPartyNotices.txt",
        ]
        substrate = r / "Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate"
        substrate_info = plistlib.loads((substrate.parent / "Info.plist").read_bytes())
        assert substrate_info["CFBundleIdentifier"] == "com.saurik.CydiaSubstate"
        assert substrate_info["CFBundleVersion"] == "0.9.7113"
        assert (
            subprocess.check_output(
                ["lipo", "-archs", str(substrate)], text=True
            ).strip()
            == "arm64"
        )
        substrate_links = subprocess.check_output(
            ["otool", "-L", str(substrate)], text=True
        )
        assert "@rpath/CydiaSubstrate.framework/CydiaSubstrate" in substrate_links
        for line in substrate_links.splitlines()[2:]:
            assert line.strip().startswith(
                ("/System/Library/Frameworks/", "/usr/lib/")
            ), line
        deps = subprocess.check_output(
            ["dpkg-deb", "-f", str(deb), "Depends"], text=True
        ).strip()
        assert deps == "firmware (>= 15.0)", deps
        subprocess.run(["dpkg-deb", "-e", str(deb), str(r / "control")], check=True)
        assert not any(
            (r / "control" / n).exists()
            for n in ("postinst", "prerm", "preinst", "postrm")
        )
        linked = subprocess.check_output(["otool", "-L", str(binary)], text=True)
        assert "@rpath/GunshotJailed.dylib" in linked, linked
        dependencies = "\n".join(linked.splitlines()[2:])
        for name in (
            "rocketbootstrap",
            "libsandy",
            "substrate",
            "ellekit",
            "Preferences.framework",
            "/var/jb/",
        ):
            assert name.lower() not in dependencies.lower(), linked
        for line in linked.splitlines()[2:]:
            assert line.strip().startswith(
                ("/System/Library/Frameworks/", "/usr/lib/")
            ), line
        assert (
            subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip()
            == "arm64"
        )
        sys.exit(0)
    r = Path(d) / prefix
    deps = subprocess.check_output(["dpkg-deb", "-f", str(deb), "Depends"], text=True)
    assert "com.opa334.libsandy (>= 1.1.6)" in deps, deps
    assert "rocketbootstrap" not in deps.lower(), deps
    assert "preferenceloader" not in deps.lower(), deps
    assert not (r / "Library/PreferenceLoader/Preferences/Gunshot.plist").exists()
    assert not (r / "Library/PreferenceBundles/GunshotPrefs.bundle").exists()
    profile = r / "Library/libSandy/dev.tqmane.gunshot.ipc.plist"
    assert profile.stat().st_mode & 0o777 == 0o644
    assert plistlib.loads(profile.read_bytes()) == {
        "AllowedProcesses": ["com.google.photos", "com.apple.mobileslideshow"],
        "Extensions": [
            {
                "type": "mach",
                "extension_class": "com.apple.app-sandbox.mach",
                "mach_name": "dev.tqmane.gunshot.service",
            },
            {
                "type": "mach",
                "extension_class": "com.apple.security.exception.mach-lookup.global-name",
                "mach_name": "dev.tqmane.gunshot.service",
            },
            {
                "type": "mach",
                "extension_class": "com.apple.app-sandbox.mach",
                "mach_name": "dev.tqmane.gunshot.discovery",
            },
            {
                "type": "mach",
                "extension_class": "com.apple.security.exception.mach-lookup.global-name",
                "mach_name": "dev.tqmane.gunshot.discovery",
            },
        ],
    }
    for p in [
        "usr/libexec/gotohpd",
        "Library/MobileSubstrate/DynamicLibraries/Gunshot.dylib",
    ]:
        assert (r / p).is_file(), p
    # Both sides must work without the removed broker library or service names.
    for p in [
        "usr/libexec/gotohpd",
        "Library/MobileSubstrate/DynamicLibraries/Gunshot.dylib",
    ]:
        linked = subprocess.check_output(["otool", "-L", str(r / p)], text=True)
        assert "rocketbootstrap" not in linked.lower(), linked
        symbols = subprocess.check_output(["nm", "-u", str(r / p)], text=True)
        assert "_rocketbootstrap_" not in symbols.lower(), symbols
        strings = subprocess.check_output(["strings", str(r / p)], text=True)
        for removed in ("cy:rbs:", "com.apple.ReportCrash.SimulateCrash"):
            assert removed not in strings, f"{p}: obsolete lookup endpoint {removed}"
    for p in ["Library/MobileSubstrate/DynamicLibraries/Gunshot.dylib"]:
        verify_backup_integration(r / p)
        strings = subprocess.check_output(["strings", str(r / p)], text=True)
        assert (
            "/" + prefix + "usr/lib/libsandy.dylib" in strings.splitlines()
        ), "wrong sandbox library prefix"
        assert (
            "dev.tqmane.gunshot.ipc" in strings.splitlines()
        ), "sandbox profile missing from client"
        assert (
            "dev.tqmane.gunshot.discovery" in strings.splitlines()
        ), "XPC discovery missing from client"
    launch = plistlib.loads(
        (r / "Library/LaunchDaemons/dev.tqmane.gunshot.plist").read_bytes()
    )
    assert launch["UserName"] == "mobile"
    assert launch["MachServices"] == {
        "dev.tqmane.gunshot.service": True,
        "dev.tqmane.gunshot.discovery": True,
    }
    assert launch["ProgramArguments"] == ["/" + prefix + "usr/libexec/gotohpd"]
    assert "StandardOutPath" not in launch and "StandardErrorPath" not in launch

    assert not (r / "var/jb").exists(), "package prefix applied twice"
