#!/usr/bin/env python3
"""Stage the official Cydia Substrate runtime for jailed IPA injection."""
from pathlib import Path
import hashlib
import io
import lzma
import subprocess
import tarfile
import urllib.request

VERSION = "0.9.7113"
URL = f"https://apt.bingner.com/debs/1443.00/mobilesubstrate_{VERSION}_iphoneos-arm.deb"
SHA256 = "e7ff98de6bc273dd17ad6ca4dc71cea23d8632d8f59478b2d5e8bf1ac13aa673"
package = Path(f".build/mobilesubstrate-{VERSION}.deb")
package.parent.mkdir(exist_ok=True)
if not package.exists():
    with urllib.request.urlopen(URL, timeout=60) as response:
        package.write_bytes(response.read())
if hashlib.sha256(package.read_bytes()).hexdigest() != SHA256:
    raise SystemExit("Cydia Substrate package checksum mismatch")
data = subprocess.check_output(["ar", "-p", str(package), "data.tar.lzma"])
framework = Path(".build/CydiaSubstrate.framework")
framework.mkdir(exist_ok=True)
# Extract only these regular files, without following the jailbreak's absolute symlinks.
with tarfile.open(fileobj=io.BytesIO(lzma.decompress(data)), mode="r:") as archive:
    for source, target in (
        ("./usr/lib/libsubstrate.dylib", "CydiaSubstrate.universal"),
        ("./Library/Frameworks/CydiaSubstrate.framework/Info.plist", "Info.plist"),
    ):
        member = archive.getmember(source)
        if not member.isfile():
            raise SystemExit(f"Expected a regular file: {source}")
        (framework / target).write_bytes(archive.extractfile(member).read())
# Upstream uses an old-style plist. Modern IPA signers need XML to recognize
# this as a framework bundle and bind its signature to CFBundleIdentifier.
subprocess.run(
    ["plutil", "-convert", "xml1", str(framework / "Info.plist")], check=True
)
subprocess.run(
    [
        "plutil",
        "-insert",
        "CFBundleVersion",
        "-string",
        VERSION,
        str(framework / "Info.plist"),
    ],
    check=True,
)
binary = framework / "CydiaSubstrate"
subprocess.run(
    [
        "lipo",
        str(framework / "CydiaSubstrate.universal"),
        "-thin",
        "arm64",
        "-output",
        str(binary),
    ],
    check=True,
)
(framework / "CydiaSubstrate.universal").unlink()
subprocess.run(
    [
        "install_name_tool",
        "-id",
        "@rpath/CydiaSubstrate.framework/CydiaSubstrate",
        str(binary),
    ],
    check=True,
)
subprocess.run(["codesign", "--force", "--sign", "-", str(framework)], check=True)
