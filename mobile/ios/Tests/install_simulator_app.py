#!/usr/bin/env python3
"""Install a local simulator app, including the iOS 18.5 WebKit workaround.

Unlike a launch environment override, this also works when tapping the app icon.
Only a temporary copy is modified; device builds and simulator runtimes stay intact.
See https://bugs.webkit.org/show_bug.cgi?id=293831.
"""
import argparse
import json
import pathlib
import plistlib
import subprocess
import tempfile


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True, timeout=60).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=pathlib.Path)
    parser.add_argument('--device', required=True, help='UDID of an existing booted iOS simulator')
    parser.add_argument('--launch', action='store_true')
    args = parser.parse_args()
    app = args.app.resolve()
    if app.suffix != '.app' or not (app / 'Info.plist').is_file():
        parser.error('--app must point to a built .app directory')
    with (app / 'Info.plist').open('rb') as f:
        info = plistlib.load(f)
    if 'iPhoneSimulator' not in info.get('CFBundleSupportedPlatforms', []):
        parser.error('Only iOS simulator builds are supported')

    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', '-j'))['devices']
    selected = [(runtime, device) for runtime, entries in devices.items() for device in entries
                if device['udid'] == args.device]
    if not selected or selected[0][1]['state'] != 'Booted':
        parser.error('--device must identify a booted simulator; boot it in Device Hub first')
    runtime_id, _ = selected[0]
    runtimes = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '-j'))['runtimes']
    runtime = next(r for r in runtimes if r['identifier'] == runtime_id)
    if not runtime_id.startswith('com.apple.CoreSimulator.SimRuntime.iOS-'):
        parser.error('Only iOS simulators are supported')

    with tempfile.TemporaryDirectory(prefix='wallet-simulator-') as folder:
        staged = pathlib.Path(folder) / app.name
        run('ditto', '--norsrc', '--noextattr', str(app), str(staged))
        run('xattr', '-cr', str(staged))
        patched = []
        if runtime['version'] == '18.5':
            old = '/usr/lib/swift/libswiftWebKit.dylib'
            new = '/System/Cryptexes/OS/usr/lib/swift/libswiftWebKit.dylib'
            # Mach-O and universal binaries; skip assets and Swift module metadata.
            magic = {bytes.fromhex(value) for value in (
                'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
                'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
            for binary in sorted(staged.rglob('*')):
                if binary.is_symlink() or not binary.is_file():
                    continue
                with binary.open('rb') as f:
                    if f.read(4) not in magic:
                        continue
                dependencies = run('xcrun', 'otool', '-L', str(binary))
                if not any(line.strip().startswith(old + ' (') for line in dependencies.splitlines()):
                    continue
                if not (pathlib.Path(runtime['runtimeRoot']) / new.lstrip('/')).is_file():
                    parser.error('The iOS 18.5 runtime does not contain the expected Cryptex WebKit library')
                run('xcrun', 'install_name_tool', '-change', old, new, str(binary))
                run('codesign', '--force', '--sign', '-',
                    '--preserve-metadata=identifier,entitlements,flags', str(binary))
                patched.append(str(binary.relative_to(staged)))

        run('codesign', '--force', '--deep', '--sign', '-',
            '--preserve-metadata=identifier,entitlements,flags', str(staged))
        run('codesign', '--verify', '--deep', '--strict', str(staged))
        run('xcrun', 'simctl', 'install', args.device, str(staged))
        print(f"Installed {info['CFBundleIdentifier']} on {runtime['name']}; existing app data retained.")
        if patched:
            print('Simulator-only WebKit library path corrected in: ' + ', '.join(patched))
    if args.launch:
        print(run('xcrun', 'simctl', 'launch', '--terminate-running-process',
                  args.device, info['CFBundleIdentifier']).strip())


if __name__ == '__main__':
    main()
