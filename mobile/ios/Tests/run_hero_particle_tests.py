#!/usr/bin/env python3
"""Host the native particle suites in the workspace's minimal UIKit-capable app.
Build MyTonWallet_AirOnly/AirTests first, then pass its products directory and
an existing simulator ID. This does not touch any wallet's on-device data.
"""
import argparse
import copy
import pathlib
import plistlib
import shutil
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--products', type=pathlib.Path, required=True)
p.add_argument('--device', required=True)
p.add_argument('--result', type=pathlib.Path, required=True)
p.add_argument('--swift-fallback', default='')
a = p.parse_args()
products = a.products.resolve()
source = next(products.glob('MyTonWallet_AirOnly_AirTests_*.xctestrun'))
with source.open('rb') as f:
    data = plistlib.load(f)
config = data['TestConfigurations'][0]
target = copy.deepcopy(next(t for t in config['TestTargets'] if t['BlueprintName'] == 'UIComponentsTests'))
build = products / 'Debug-iphonesimulator'
host = build / 'HeroParticleTestHost.app'
if host.exists():
    shutil.rmtree(host)
shutil.copytree(build / 'KeychainTestHost.app', host, symlinks=True)
test = host / 'PlugIns/UIComponentsTests.xctest'
shutil.copytree(build / 'UIComponentsTests.xctest', test, symlinks=True)
for attribute in ['com.apple.FinderInfo', 'com.apple.ResourceFork']:
    subprocess.run(['xattr', '-rd', attribute, str(host)], check=True)
subprocess.run(['codesign', '--force', '--deep', '--strip-disallowed-xattrs', '--sign', '-', str(host)], check=True)
target.update({
    'TestHostPath': '__TESTROOT__/Debug-iphonesimulator/HeroParticleTestHost.app',
    'TestHostBundleIdentifier': 'org.mytonwallet.KeychainTestHost',
    'TestBundlePath': '__TESTHOST__/PlugIns/UIComponentsTests.xctest',
    'IsAppHostedTestBundle': True,
    'InProcessParallelizationEnabled': False,
    'DependentProductPaths': [str(host), str(test)],
})
env = target['TestingEnvironmentVariables']
env['DYLD_INSERT_LIBRARIES'] = '__TESTHOST__/Frameworks/libXCTestBundleInject.dylib:/usr/lib/libRPAC.dylib'
env['XCInjectBundleInto'] = 'unused'
if a.swift_fallback:
    target['EnvironmentVariables']['DYLD_FALLBACK_LIBRARY_PATH'] = a.swift_fallback
config['TestTargets'] = [target]
data['TestConfigurations'] = [config]
runner = products / 'HeroParticlesHosted.xctestrun'
with runner.open('wb') as f:
    plistlib.dump(data, f)
command = ['xcodebuild', 'test-without-building', '-xctestrun', str(runner),
    '-destination', 'platform=iOS Simulator,id=' + a.device,
    '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
    '-resultBundlePath', str(a.result), '-only-testing:UIComponentsTests/HeroParticleTests']
raise SystemExit(subprocess.run(command).returncode)
