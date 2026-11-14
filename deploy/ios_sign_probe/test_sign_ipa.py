import os
import plistlib
import stat
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
APP = 'My Wallet_Preview.app'
WIDGET = 'PlugIns/AirWidgetExtension_Preview.appex'
NOTIFICATION = 'PlugIns/MyTonWalletNotificationServiceExtension_Preview.appex'
# Like rcodesign 0.29.0, verify refuses anything that is not a Mach-O file. The PEM blocks each --pem-file
# carries are logged while the files still exist, since the script removes them on exit.
FAKE_RCODESIGN = '''#!/bin/sh
if [ "$1" = verify ] && [ -d "$2" ]; then echo "verify command only works on Mach-O binaries" >&2; exit 1; fi
echo "$@" >> "$(dirname "$0")/calls"
previous=
for arg in "$@"; do
  [ "$previous" = --pem-file ] && grep -h '^-----BEGIN' "$arg" >> "$(dirname "$0")/pems"
  previous=$arg
done
'''


class SignIpaTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=probe',
                        '-keyout', self.path('key.pem'), '-out', self.path('cert.pem')], check=True, capture_output=True)
        with open(self.path('password'), 'w') as file:
            file.write('probe-pass')
        self.p12('cert.p12', '-keypbe', 'AES-256-CBC', '-certpbe', 'AES-256-CBC', '-macalg', 'sha256')
        self.profiles = {
            'APP_PROFILE': self.profile('app', 'org.mytonwallet.app.preview'),
            'WIDGET_PROFILE': self.profile('widget', 'org.mytonwallet.app.preview.AirWidget'),
            'NOTIFICATION_PROFILE': self.profile('notification', 'org.mytonwallet.app.preview.notification-service'),
        }
        self.rcodesign = self.path('rcodesign')
        with open(self.rcodesign, 'w') as file:
            file.write(FAKE_RCODESIGN)
        os.chmod(self.rcodesign, 0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def path(self, name):
        return os.path.join(self.dir, name)

    def p12(self, name, *options):
        subprocess.run(['openssl', 'pkcs12', '-export', *options, '-in', self.path('cert.pem'), '-inkey', self.path('key.pem'),
                        '-passout', f'file:{self.path("password")}', '-out', self.path(name)], check=True, capture_output=True)
        return self.path(name)

    def pem_blocks(self):
        with open(self.path('pems')) as file:
            return [line.strip() for line in file]

    def profile(self, name, identifier):
        payload = self.path(f'{name}.plist')
        with open(payload, 'wb') as file:
            plistlib.dump({'Name': name, 'Entitlements': {
                'application-identifier': f'TEAM.{identifier}', 'com.apple.developer.team-identifier': 'TEAM',
                'get-task-allow': False, 'beta-reports-active': True, 'aps-environment': 'production',
                'com.apple.developer.associated-domains': '*',
                'com.apple.security.application-groups': ['group.org.mytonwallet.app.preview'],
            }}, file)
        signed = self.path(f'{name}.mobileprovision')
        subprocess.run(['openssl', 'smime', '-sign', '-binary', '-nodetach', '-outform', 'der', '-in', payload,
                        '-signer', self.path('cert.pem'), '-inkey', self.path('key.pem'), '-out', signed],
                       check=True, capture_output=True)
        return signed

    def bundle(self, root, relative, identifier, executable, mode=0o755):
        directory = os.path.join(root, relative)
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, 'Info.plist'), 'wb') as file:
            plistlib.dump({'CFBundleIdentifier': identifier, 'CFBundleExecutable': executable}, file, fmt=plistlib.FMT_BINARY)
        binary = os.path.join(directory, executable)
        with open(binary, 'wb') as file:
            file.write(b'\xcf\xfa\xed\xfe')
        os.chmod(binary, mode)

    def app_tar(self, widget_mode=0o755):
        root = self.path('build')
        self.bundle(root, APP, 'org.mytonwallet.app.preview', 'My Wallet_Preview')
        self.bundle(root, f'{APP}/{WIDGET}', 'org.mytonwallet.app.preview.AirWidget', 'AirWidgetExtension_Preview', widget_mode)
        self.bundle(root, f'{APP}/{NOTIFICATION}', 'org.mytonwallet.app.preview.notification-service',
                    'MyTonWalletNotificationServiceExtension_Preview')
        archive = self.path('app.tar')
        with tarfile.open(archive, 'w') as tar:
            tar.add(os.path.join(root, APP), arcname=APP)
        return archive

    def run_script(self, archive, **overrides):
        env = dict(os.environ, P12_PATH=self.path('cert.p12'), P12_PASSWORD_FILE=self.path('password'), TEAM_ID='TEAM',
                   ENTITLEMENTS_DIR=os.path.join(REPO, 'mobile/ios/App/Entitlements'), RCODESIGN=self.rcodesign,
                   **self.profiles)
        env.update(overrides)
        return subprocess.run(['bash', os.path.join(HERE, 'sign_ipa.sh'), archive, self.path('out.ipa')],
                              env=env, capture_output=True, text=True)

    def test_signs_each_bundle_with_its_own_profile_and_entitlements(self):
        result = self.run_script(self.app_tar())

        self.assertEqual(0, result.returncode, result.stderr)
        with open(self.path('calls')) as file:
            sign = file.readline().split()
        self.assertEqual('sign', sign[0])
        self.assertIn('--team-name TEAM', ' '.join(sign))
        self.assertIn('--timestamp-url none', ' '.join(sign))
        scoped = [sign[i + 1] for i, arg in enumerate(sign) if arg == '-e']
        self.assertEqual(3, len(scoped))
        self.assertTrue(any(value.startswith(f'{WIDGET}:') for value in scoped), scoped)
        self.assertTrue(any(value.startswith(f'{NOTIFICATION}:') for value in scoped), scoped)
        with zipfile.ZipFile(self.path('out.ipa')) as ipa:
            names = set(ipa.namelist())
        for bundle in (APP, f'{APP}/{WIDGET}', f'{APP}/{NOTIFICATION}'):
            self.assertIn(f'Payload/{bundle}/embedded.mobileprovision', names)

    def test_refuses_a_profile_issued_for_another_bundle(self):
        result = self.run_script(self.app_tar(), WIDGET_PROFILE=self.profiles['APP_PROFILE'])

        self.assertEqual(1, result.returncode)
        self.assertIn('is issued for TEAM.org.mytonwallet.app.preview, not TEAM.org.mytonwallet.app.preview.AirWidget',
                      result.stderr)
        self.assertFalse(os.path.exists(self.path('calls')))

    def test_refuses_a_bundle_that_lost_its_executable_bit(self):
        result = self.run_script(self.app_tar(widget_mode=0o644))

        self.assertEqual(1, result.returncode)
        self.assertIn('AirWidgetExtension_Preview is not executable', result.stderr)

    def test_signs_with_the_identity_unpacked_from_a_modern_p12(self):
        result = self.run_script(self.app_tar())

        self.assertEqual(0, result.returncode, result.stderr)
        with open(self.path('calls')) as file:
            sign = file.readline()
        self.assertNotIn('--p12-file', sign)
        self.assertEqual(['-----BEGIN PRIVATE KEY-----', '-----BEGIN CERTIFICATE-----'], self.pem_blocks())
        self.assertIn('MAC: sha256', result.stdout)
        self.assertIn('PBES2', result.stdout)

    def test_unpacks_a_legacy_p12_too(self):
        result = self.run_script(self.app_tar(), P12_PATH=self.p12('legacy.p12', '-legacy'))

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(['-----BEGIN PRIVATE KEY-----', '-----BEGIN CERTIFICATE-----'], self.pem_blocks())
        self.assertIn('MAC: sha1', result.stdout)

    def test_refuses_a_p12_the_password_does_not_open(self):
        with open(self.path('wrong'), 'w') as file:
            file.write('not-the-password')

        result = self.run_script(self.app_tar(), P12_PASSWORD_FILE=self.path('wrong'))

        self.assertEqual(1, result.returncode)
        self.assertIn('cannot open', result.stderr)
        self.assertFalse(os.path.exists(self.path('calls')))


if __name__ == '__main__':
    unittest.main()
