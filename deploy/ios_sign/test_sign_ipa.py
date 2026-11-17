import os
import plistlib
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from unpack_app import MAX_MEMBERS  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
APP = 'My Wallet_Preview.app'
VERSION = '26.11.2'
BUILD = '10000010'
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

    def bundle(self, root, relative, identifier, executable, mode=0o755, build=BUILD):
        directory = os.path.join(root, relative)
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, 'Info.plist'), 'wb') as file:
            plistlib.dump({'CFBundleIdentifier': identifier, 'CFBundleExecutable': executable,
                           'CFBundleShortVersionString': VERSION, 'CFBundleVersion': build}, file, fmt=plistlib.FMT_BINARY)
        binary = os.path.join(directory, executable)
        os.makedirs(os.path.dirname(binary), exist_ok=True)
        with open(binary, 'wb') as file:
            file.write(b'\xcf\xfa\xed\xfe')
        os.chmod(binary, mode)

    def app_tar(self, widget_mode=0o755, extra=(), build=BUILD, widget_executable='AirWidgetExtension_Preview',
                headers=()):
        root = self.path('build')
        self.bundle(root, APP, 'org.mytonwallet.app.preview', 'My Wallet_Preview', build=build)
        self.bundle(root, f'{APP}/{WIDGET}', 'org.mytonwallet.app.preview.AirWidget', widget_executable, widget_mode)
        self.bundle(root, f'{APP}/{NOTIFICATION}', 'org.mytonwallet.app.preview.notification-service',
                    'MyTonWalletNotificationServiceExtension_Preview')
        archive = self.path('app.tar')
        with tarfile.open(archive, 'w') as tar:
            tar.add(os.path.join(root, APP), arcname=APP)
            for member in extra:
                tar.addfile(member)
            # A bare header declares a size without the bytes behind it, as a crafted archive can.
            for header in headers:
                block = header.tobuf(tar.format, tar.encoding, tar.errors)
                tar.fileobj.write(block)
                tar.offset += len(block)
        return archive

    def member(self, name, kind=tarfile.REGTYPE, target=''):
        info = tarfile.TarInfo(name)
        info.type = kind
        info.linkname = target
        return info

    def run_script(self, archive, **overrides):
        env = dict(os.environ, P12_PATH=self.path('cert.p12'), P12_PASSWORD_FILE=self.path('password'), TEAM_ID='TEAM',
                   ENTITLEMENTS_DIR=os.path.join(REPO, 'mobile/ios/App/Entitlements'), RCODESIGN=self.rcodesign,
                   EXPECT_VERSION=VERSION, EXPECT_BUILD=BUILD, **self.profiles)
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

    def test_the_ipa_carries_only_the_signed_app(self):
        result = self.run_script(self.app_tar(extra=[self.member('beside.txt'), self.member('Folder')]))

        self.assertEqual(0, result.returncode, result.stderr)
        with zipfile.ZipFile(self.path('out.ipa')) as ipa:
            strays = [name for name in ipa.namelist() if not name.startswith(f'Payload/{APP}/')]
        self.assertEqual(['Payload/'], strays)

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

    def assert_refused(self, result, cause):
        self.assertEqual(1, result.returncode, result.stdout)
        self.assertIn(cause, result.stderr)
        self.assertFalse(os.path.exists(self.path('calls')))

    def test_refuses_a_member_with_an_absolute_path(self):
        escaped = self.path('escaped')

        result = self.run_script(self.app_tar(extra=[self.member(escaped)]))

        self.assert_refused(result, 'absolute path')
        self.assertFalse(os.path.exists(escaped))

    def test_refuses_a_member_climbing_out_with_dotdot(self):
        result = self.run_script(self.app_tar(extra=[self.member(f'{APP}/../../escaped')]))

        self.assert_refused(result, 'leaves the archive')
        self.assertFalse(os.path.exists(self.path('escaped')))

    def test_refuses_any_symlink(self):
        for name, target in ((f'{APP}/link', '/etc'), (f'{APP}/link', '../outside'),
                             (f'{APP}/inner', 'Info.plist'), (f'{APP}/up', 'PlugIns/..')):
            with self.subTest(name=name, target=target):
                result = self.run_script(self.app_tar(extra=[self.member(name, tarfile.SYMTYPE, target)]))

                self.assert_refused(result, 'is a symlink')

    def test_a_value_from_the_archive_cannot_start_a_workflow_command(self):
        result = self.run_script(self.app_tar(), EXPECT_BUILD='10000020', EXPECT_VERSION=VERSION)
        forged = self.run_script(self.app_tar(build='10000010\n::warning::forged'), EXPECT_BUILD='10000020')

        self.assert_refused(result, 'expected 10000020')
        self.assertEqual(1, forged.returncode)
        self.assertNotIn('\n::warning::forged', forged.stderr)
        self.assertIn('%0A::warning::forged', forged.stderr)

    def test_workflow_commands_are_off_while_rcodesign_reads_the_archive(self):
        result = self.run_script(self.app_tar())

        self.assertEqual(0, result.returncode, result.stderr)
        lines = result.stdout.splitlines()
        stops = [line for line in lines if line.startswith('::stop-commands::')]
        self.assertEqual(1, len(stops), result.stdout)
        token = stops[0].split('::')[2]
        self.assertGreaterEqual(len(token), 32)
        self.assertIn(f'::{token}::', lines)
        self.assertLess(lines.index(stops[0]), lines.index(f'::{token}::'))

    def test_refuses_a_name_carrying_a_control_character(self):
        for name in (f'{APP}/a\n::warning::forged', f'B\n::warning::forged.app/Info.plist', f'{APP}/bell\x07'):
            with self.subTest(name=name):
                result = self.run_script(self.app_tar(extra=[self.member(name)]))

                self.assert_refused(result, 'control character')
                self.assertNotIn('\n::warning::forged', result.stdout + result.stderr)

    def test_refuses_an_executable_named_by_a_path(self):
        for executable in ('../Outside', 'Nested/Binary', '.hidden'):
            with self.subTest(executable=executable):
                result = self.run_script(self.app_tar(widget_executable=executable))

                self.assert_refused(result, 'not a plain file name')

    def test_refuses_an_archive_larger_than_an_app_can_be(self):
        huge = self.member(f'{APP}/huge')
        huge.size = 5 << 30

        result = self.run_script(self.app_tar(headers=[huge]))

        self.assert_refused(result, 'larger than')

    def test_refuses_an_archive_with_more_entries_than_an_app_has(self):
        empties = [self.member(f'{APP}/empty-{index}') for index in range(MAX_MEMBERS)]

        result = self.run_script(self.app_tar(headers=empties))

        self.assert_refused(result, 'more than')

    def test_refuses_a_hard_link(self):
        result = self.run_script(self.app_tar(extra=[self.member(f'{APP}/hard', tarfile.LNKTYPE, f'{APP}/Info.plist')]))

        self.assert_refused(result, 'hard link')

    def test_refuses_a_build_number_other_than_expected(self):
        result = self.run_script(self.app_tar(), EXPECT_BUILD='10000020')

        self.assert_refused(result, 'CFBundleVersion 10000010, expected 10000020')

    def test_refuses_a_version_other_than_expected(self):
        result = self.run_script(self.app_tar(), EXPECT_VERSION='26.11.3')

        self.assert_refused(result, 'CFBundleShortVersionString 26.11.2, expected 26.11.3')


if __name__ == '__main__':
    unittest.main()
