"""Generate small diagnostic files for the native parser tests."""
import io
import json
import pathlib
import plistlib
import sys
import tarfile
import zipfile

root = pathlib.Path(sys.argv[1])
root.mkdir(exist_ok=True, parents=True)
for kind, code, record in [('crash', '309', {'procName': 'Demo'}), ('panic', '210', {'panicString': 'Sample panic'}),
                           ('jetsam', '298', {'processes': [{'name': 'Sample', 'rpages': 3}]}),
                           ('analytics', '211', {'message': 'Sample event'})]:
    (root / kind).write_text(json.dumps({'bug_type': code}) + '\n' + json.dumps(record, indent=2))
with tarfile.open(root / 'sysdiagnose.tar.gz', 'w:gz') as archive:
    info = tarfile.TarInfo('logs/summary.txt')
    info.size = 5
    archive.addfile(info, io.BytesIO(b'hello'))
with zipfile.ZipFile(root / 'sample.ipsw', 'w', zipfile.ZIP_DEFLATED) as archive:
    archive.writestr('Restore.plist', plistlib.dumps({'ProductVersion': '16.6', 'ProductBuildVersion': '20G75'}))
(root / 'broken.zip').write_bytes(b'PK\x03\x04broken')
