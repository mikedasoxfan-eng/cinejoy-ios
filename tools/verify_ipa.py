"""Check an actual unsigned device IPA, without installing or executing it."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

ipa = Path(sys.argv[1])
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, "Archive CRC check failed"
    plists = [name for name in archive.namelist() if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
    assert len(plists) == 1, "Expected one application payload"
    root = plists[0].removesuffix("Info.plist")
    info = plistlib.loads(archive.read(plists[0]))
    binary = archive.read(root + info["CFBundleExecutable"])
    header = struct.unpack_from("<8I", binary)
    assert header[0] == 0xFEEDFACF, "Expected a 64-bit Mach-O"
    assert header[1] == 0x0100000C, "Expected an ARM64 device executable"
    assert header[3] == 2, "Mach-O is not an executable"
    offset = 32
    platform = None
    for _ in range(header[4]):
        command, length = struct.unpack_from("<II", binary, offset)
        if command == 0x32:
            platform, minimum, sdk, _ = struct.unpack_from("<4I", binary, offset + 8)
        offset += length
    assert platform == 2, "This is not an iOS device binary"
    assert info["MinimumOSVersion"].startswith("26."), "Unexpected minimum iOS version"
    assert "NSLocalNetworkUsageDescription" not in info, "Local-network permission was not removed"
    assert info.get("UIBackgroundModes") == ["audio"], "Media background mode is missing"
    for resource in ["CatalogSeed.json", "CatalogExtraction.js", "SeasonSelection.js", "PlayerIntegration.js", "Assets.car"]:
        assert root + resource in archive.namelist(), f"Missing packaged resource: {resource}"
    script = archive.read(root + "PlayerIntegration.js").decode()
    assert "disableRemotePlayback=true" in script and "x-webkit-airplay" in script
    assert 'button[aria-label="Cast to Device"]' in script
    catalog = archive.read(root + "CatalogSeed.json").decode()
    assert "api_key" not in catalog and "cinejoy_token" not in catalog
    output = dict(
        file=str(ipa.resolve()), bytes=ipa.stat().st_size,
        sha256=hashlib.sha256(ipa.read_bytes()).hexdigest(),
        bundle_identifier=info["CFBundleIdentifier"], minimum_ios=info["MinimumOSVersion"],
        architecture="arm64", platform="iOS device", resources_verified=True,
        casting_control_removed=True, local_network_permission=False,
        signed=any(name.startswith(root + "_CodeSignature/") for name in archive.namelist()),
        background_modes=info.get("UIBackgroundModes", []),
    )
print(json.dumps(output, indent=2))
