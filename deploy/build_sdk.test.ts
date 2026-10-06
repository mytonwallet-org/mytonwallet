import fs from 'fs';
import path from 'path';

const script = fs.readFileSync(path.resolve(__dirname, 'build_sdk.sh'), 'utf8');

describe('build_sdk.sh', () => {
  // The Agent host reaches the SDK only through `defineEnv`, which runs inside `vite build`.
  // Resolving it afterwards validates a value nothing reads, and the bundle silently keeps the
  // production default from src/config.ts - which is how a TestFlight build of the beta app
  // shipped talking to the production Agent.
  it('settles the Agent host before the bundles are built', () => {
    const exported = script.indexOf('export AGENT_API_URL');
    const firstBuild = script.indexOf('vite build');

    expect(exported).toBeGreaterThan(-1);
    expect(firstBuild).toBeGreaterThan(-1);
    expect(exported).toBeLessThan(firstBuild);
  });

  // An unset repository variable expands to an empty string, and an empty string is a value
  // `defineEnv` keeps, so without this the production default is what ships.
  it('refuses an empty Agent host in CI instead of defaulting to production', () => {
    const guard = script.indexOf('if [ -n "${CI:-}" ] && [ -z "${AGENT_API_URL:-}" ]; then');
    expect(guard).toBeGreaterThan(-1);
    expect(script.slice(guard, guard + 400)).toContain('exit 1');
  });

  // Every other check in the script runs before the copy, so a target directory that kept an older
  // bundle passes all of them. Reading the copies back is the only step that can see that.
  it('reads the shipped copies back after copying them', () => {
    const lastCopy = script.lastIndexOf('cp dist-air/');
    const readback = script.indexOf('report_sdk_assets.js');

    expect(readback).toBeGreaterThan(-1);
    expect(readback).toBeGreaterThan(lastCopy);
  });
});
