"""Create a local signing key once. Never print passwords or overwrite keys."""
import os
from pathlib import Path
import secrets
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
android = ROOT / 'mobile/android'
properties = android / 'key.properties'
keystore = android / 'keystore/adam-run-release.jks'
if properties.exists() and keystore.exists():
    print('Existing release signing files retained.')
    raise SystemExit(0)
if properties.exists() or keystore.exists():
    raise SystemExit('Incomplete signing setup. Restore the matching key and properties; refusing to overwrite.')
keytool = str(Path(os.environ['JAVA_HOME']) / 'bin/keytool') if os.environ.get('JAVA_HOME') else shutil.which('keytool')
if not keytool:
    raise SystemExit('Install Java 21 and set JAVA_HOME.')
os.umask(0o077)
keystore.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
password = secrets.token_urlsafe(48)
env = {**os.environ, 'ADAM_SIGN_PASSWORD': password}
subprocess.run([
    keytool, '-genkeypair', '-keystore', str(keystore), '-storetype', 'PKCS12',
    '-alias', 'adam-run', '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
    '-storepass:env', 'ADAM_SIGN_PASSWORD', '-keypass:env', 'ADAM_SIGN_PASSWORD',
    '-dname', 'CN=ADAM RUN, OU=Mobile, O=ADAM RUN, L=Bishkek, C=KG', '-noprompt',
], env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
properties.write_text(
    f'storePassword={password}\nkeyPassword={password}\nkeyAlias=adam-run\n'
    'storeFile=keystore/adam-run-release.jks\n'
)
keystore.chmod(0o600)
properties.chmod(0o600)
print('Release signing key created. Back up mobile/android/key.properties and mobile/android/keystore securely; both are excluded from Git.')
