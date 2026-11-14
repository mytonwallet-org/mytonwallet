import os
import plistlib
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from merge_entitlements import merge_entitlements  # noqa: E402

APP_SOURCE = {
    'aps-environment': 'development',
    'com.apple.developer.associated-domains': [
        'applinks:connect.mywallet.io',
        'applinks:connect.mytonwallet.org',
        'applinks:go.mytonwallet.org',
        'applinks:my.tt',
    ],
    'com.apple.security.application-groups': ['group.org.mytonwallet.app.preview'],
}
WIDGET_SOURCE = {
    'com.apple.security.application-groups': ['group.org.mytonwallet.app.preview'],
}
APP_PROFILE = {
    'application-identifier': 'TEAM.org.mytonwallet.app.preview',
    'com.apple.developer.team-identifier': 'TEAM',
    'keychain-access-groups': ['TEAM.*'],
    'get-task-allow': False,
    'beta-reports-active': True,
    'aps-environment': 'production',
    'com.apple.developer.associated-domains': '*',
    'com.apple.security.application-groups': ['group.org.mytonwallet.app.preview'],
    'com.apple.developer.icloud-container-identifiers': [],
}


class MergeEntitlementsTest(unittest.TestCase):
    def test_identifiers_come_from_the_profile(self):
        merged = merge_entitlements(APP_SOURCE, APP_PROFILE)

        self.assertEqual('TEAM.org.mytonwallet.app.preview', merged['application-identifier'])
        self.assertEqual('TEAM', merged['com.apple.developer.team-identifier'])
        self.assertIs(False, merged['get-task-allow'])
        self.assertIs(True, merged['beta-reports-active'])

    def test_concrete_values_come_from_the_source(self):
        merged = merge_entitlements(APP_SOURCE, APP_PROFILE)

        self.assertEqual(APP_SOURCE['com.apple.developer.associated-domains'],
                         merged['com.apple.developer.associated-domains'])
        self.assertEqual(['group.org.mytonwallet.app.preview'], merged['com.apple.security.application-groups'])

    def test_aps_environment_follows_the_profile(self):
        self.assertEqual('production', merge_entitlements(APP_SOURCE, APP_PROFILE)['aps-environment'])
        self.assertNotIn('aps-environment', merge_entitlements(WIDGET_SOURCE, APP_PROFILE))

    def test_rejects_what_the_profile_does_not_grant(self):
        source = dict(APP_SOURCE, **{'com.apple.developer.icloud-services': ['CloudKit']})

        with self.assertRaises(ValueError) as raised:
            merge_entitlements(source, APP_PROFILE)
        self.assertIn('com.apple.developer.icloud-services', str(raised.exception))

    def test_rejects_a_value_the_profile_does_not_grant(self):
        profile = dict(APP_PROFILE, **{'com.apple.security.application-groups': ['group.org.mytonwallet.app']})

        with self.assertRaises(ValueError) as raised:
            merge_entitlements(WIDGET_SOURCE, profile)
        self.assertIn('group.org.mytonwallet.app.preview', str(raised.exception))

    def test_wildcard_grants_cover_concrete_values(self):
        profile = dict(APP_PROFILE, **{'com.apple.security.application-groups': ['group.org.mytonwallet.*']})

        merged = merge_entitlements(APP_SOURCE, profile)

        self.assertEqual(['group.org.mytonwallet.app.preview'], merged['com.apple.security.application-groups'])

    def test_profile_only_keys_stay_out(self):
        merged = merge_entitlements(WIDGET_SOURCE, APP_PROFILE)

        self.assertNotIn('com.apple.developer.icloud-container-identifiers', merged)
        self.assertNotIn('com.apple.developer.associated-domains', merged)

    def test_keychain_group_is_the_concrete_application_identifier(self):
        merged = merge_entitlements(WIDGET_SOURCE, APP_PROFILE)

        self.assertEqual(['TEAM.org.mytonwallet.app.preview'], merged['keychain-access-groups'])

    def test_no_keychain_group_unless_the_profile_grants_one(self):
        profile = {key: value for key, value in APP_PROFILE.items() if key != 'keychain-access-groups'}

        self.assertNotIn('keychain-access-groups', merge_entitlements(WIDGET_SOURCE, profile))

    def test_rejects_a_keychain_group_the_profile_does_not_grant(self):
        profile = dict(APP_PROFILE, **{'keychain-access-groups': ['TEAM.org.mytonwallet.other']})

        with self.assertRaises(ValueError) as raised:
            merge_entitlements(WIDGET_SOURCE, profile)
        self.assertIn("keychain-access-groups = ['TEAM.org.mytonwallet.app.preview']", str(raised.exception))

    def test_cli_reads_the_profile_entitlements_and_writes_a_plist(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, profile, out = (os.path.join(tmp, name) for name in ('src.plist', 'profile.plist', 'out.plist'))
            with open(source, 'wb') as file:
                plistlib.dump(WIDGET_SOURCE, file)
            with open(profile, 'wb') as file:
                plistlib.dump({'Name': 'Preview Widget', 'Entitlements': APP_PROFILE}, file)

            subprocess.run([sys.executable, os.path.join(HERE, 'merge_entitlements.py'), source, profile, out], check=True)

            with open(out, 'rb') as file:
                written = plistlib.load(file)
        self.assertEqual('TEAM.org.mytonwallet.app.preview', written['application-identifier'])
        self.assertEqual(['group.org.mytonwallet.app.preview'], written['com.apple.security.application-groups'])


if __name__ == '__main__':
    unittest.main()
