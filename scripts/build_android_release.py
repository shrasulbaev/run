"""Build the signed APK against an already deployed HTTPS API."""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urlsplit
from urllib.request import urlopen

parser = argparse.ArgumentParser()
parser.add_argument('--api-url', required=True)
parser.add_argument('--flutter', default=os.environ.get('FLUTTER_BIN', 'flutter'))
args = parser.parse_args()
api_url = args.api_url.rstrip('/')
url = urlsplit(api_url)
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path:
    parser.error('--api-url must be the HTTPS origin of the deployed API, without credentials or a path.')
if url.hostname == 'localhost' or url.hostname.endswith(('.localhost', '.local')):
    parser.error('A phone build requires a public server address.')
try:
    address = ipaddress.ip_address(url.hostname)
except ValueError:
    pass
else:
    if not address.is_global:
        parser.error('A phone build requires a public server address.')
root = Path(__file__).resolve().parents[1]
if not (root / 'mobile/android/key.properties').exists():
    parser.error('Create signing files with scripts/create_android_signing.py first.')
with urlopen(api_url + '/health', timeout=120) as response:
    health = json.load(response)
if health.get('status') != 'ok' or health.get('environment') != 'demo' or health.get('test_auth') is not True:
    parser.error('The endpoint is not the healthy ADAM RUN demo API.')
subprocess.run([
    args.flutter, 'build', 'apk', '--release', '--no-pub',
    '--build-number=2', f'--dart-define=API_BASE_URL={api_url}',
], cwd=root / 'mobile', check=True)
output = root / 'artifacts/adam-run-1.0.0-demo.apk'
output.parent.mkdir(exist_ok=True)
shutil.copy2(root / 'mobile/build/app/outputs/flutter-apk/app-release.apk', output)
checksum = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix('.apk.sha256').write_text(f'{checksum}  {output.name}\n')
print(json.dumps({'apk': str(output), 'api_url': api_url, 'sha256': checksum}, ensure_ascii=False))
