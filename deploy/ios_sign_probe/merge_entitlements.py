import plistlib
import sys
from fnmatch import fnmatchcase

IDENTITY_KEYS = (
    'application-identifier',
    'com.apple.developer.team-identifier',
    'get-task-allow',
    'beta-reports-active',
)
# The profile holds the distribution value; the source file keeps the development one for local builds.
PROFILE_VALUED_KEYS = ('aps-environment',)


def _granted(value, grant):
    values = value if isinstance(value, list) else [value]
    grants = grant if isinstance(grant, list) else [grant]
    return all(any(fnmatchcase(item, pattern) if isinstance(item, str) and isinstance(pattern, str) else item == pattern
                   for pattern in grants) for item in values)


def merge_entitlements(source, profile_entitlements):
    merged = dict(source)
    for key in PROFILE_VALUED_KEYS:
        if key in source and key in profile_entitlements:
            merged[key] = profile_entitlements[key]
    for key in IDENTITY_KEYS:
        if key in profile_entitlements:
            merged[key] = profile_entitlements[key]
    # The profile grants the wildcard TEAM.*; Xcode signs the concrete group, as the SDK's base entitlements do.
    if 'keychain-access-groups' in profile_entitlements:
        merged['keychain-access-groups'] = [profile_entitlements['application-identifier']]

    # Checked on the result, so a value the merge derives itself is held to the profile too.
    refused = [key if key not in profile_entitlements else f'{key} = {merged[key]!r}'
               for key in sorted(merged)
               if key not in profile_entitlements or not _granted(merged[key], profile_entitlements[key])]
    if refused:
        raise ValueError(f"the provisioning profile does not grant {', '.join(refused)}")
    return merged


def main(source_path, profile_path, out_path):
    with open(source_path, 'rb') as file:
        source = plistlib.load(file)
    with open(profile_path, 'rb') as file:
        profile = plistlib.load(file)
    with open(out_path, 'wb') as file:
        plistlib.dump(merge_entitlements(source, profile['Entitlements']), file)


if __name__ == '__main__':
    main(*sys.argv[1:])
