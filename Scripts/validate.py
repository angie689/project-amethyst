"""Check the final archive, its application metadata and its device executable."""
import plistlib
import sys
import zipfile
from pathlib import PurePosixPath


def validate(path):
    with zipfile.ZipFile(path) as ipa:
        root = 'Payload/Amethyst.app/'
        names = ipa.namelist()
        if ipa.testzip() or len(names) != len(set(names)):
            raise ValueError("Corrupt or duplicate archive member")
        for name in names:
            if '..' in PurePosixPath(name).parts or not (name.startswith(root) or name == 'Payload/'):
                raise ValueError(f"Unexpected Payload member: {name}")
        info = plistlib.loads(ipa.read(root + 'Info.plist'))
        if info['CFBundlePackageType'] != 'APPL' or info['CFBundleSupportedPlatforms'] != ['iPhoneOS']:
            raise ValueError("Expected a device application")
        executable = info['CFBundleExecutable']
        if '/' in executable or not executable:
            raise ValueError("Invalid executable name")
        item = ipa.getinfo(root + executable)
        with ipa.open(item) as stream:
            if stream.read(8) != bytes.fromhex('cffaedfe0c000001') or not (item.external_attr >> 16 & 0o111):
                raise ValueError("Expected executable arm64 Mach-O")
        for resource in ['catalog.json', 'PrivacyInfo.xcprivacy', 'Assets.car']:
            ipa.getinfo(root + resource)


if __name__ == '__main__':
    try:
        validate(sys.argv[1])
    except Exception as error:
        sys.exit(f"IPA validation failed: {error}")
