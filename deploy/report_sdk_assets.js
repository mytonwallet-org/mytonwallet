/**
 * Reports what each shipped copy of an SDK bundle actually contains, and stops the build when a copy
 * is not the bundle this run produced.
 *
 * Everything the build checks before this point describes an intention: the Agent host was validated,
 * the bundles were built, the copies were issued. None of it can see a target directory that still
 * holds an older bundle, and that is the failure that reached TestFlight - an installed app running
 * JS six weeks older than the wrapper around it, with the copy step sitting green in the job log.
 *
 * The build stamp printed here is the same token the running app logs as it loads, so the two can be
 * compared directly: a device reporting a stamp this job never printed is running something else.
 */

const crypto = require('crypto');
const fs = require('fs');

// `<short commit>[-dirty] <date> <time>`, or `nogit` in a tree without history. See dev/buildStamp.ts.
// The commit is matched by shape rather than by length: `git rev-parse --short=9` returns more than
// nine characters whenever nine would be ambiguous, and a stamp this misses fails the build outright.
const BUILD_STAMP = /\b(?:[0-9a-f]{7,40}(?:-dirty)?|nogit) \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\b/;

function describeBundle(text) {
  const stamp = text.match(BUILD_STAMP);

  return {
    sha256: crypto.createHash('sha256').update(text).digest('hex').slice(0, 16),
    bytes: Buffer.byteLength(text),
    stamp: stamp ? stamp[0] : undefined,
  };
}

function formatBundle(file, bundle) {
  return `  ${file}\n    sha256=${bundle.sha256} bytes=${bundle.bytes} stamp=${bundle.stamp || '<absent>'}`;
}

function main(argv) {
  const [source, ...copies] = argv;
  const agentApiUrl = process.env.AGENT_API_URL;
  if (!source || !agentApiUrl) {
    throw new Error('Usage: AGENT_API_URL=<url> node deploy/report_sdk_assets.js <built bundle> <shipped copy>...');
  }

  const built = fs.readFileSync(source, 'utf8');
  const origin = describeBundle(built);
  const problems = [];

  console.log(formatBundle(source, origin));

  if (!origin.stamp) {
    problems.push(`${source} carries no build stamp, so nothing it ships can be identified at runtime`);
  }
  // The host is baked in by `defineEnv` and unreachable afterwards, so its absence here means the
  // bundle is talking to some other Agent than the one this job resolved.
  if (!built.includes(agentApiUrl)) {
    problems.push(`${source} does not contain the Agent host this build resolved (${agentApiUrl})`);
  }

  for (const copy of copies) {
    if (!fs.existsSync(copy)) {
      problems.push(`${copy} is missing, so the platform would ship whatever it already had`);
      continue;
    }

    const shipped = describeBundle(fs.readFileSync(copy, 'utf8'));
    console.log(formatBundle(copy, shipped));

    if (shipped.sha256 !== origin.sha256) {
      problems.push(`${copy} is not the bundle just built (${shipped.sha256} instead of ${origin.sha256})`);
    }
  }

  return problems;
}

if (require.main === module) {
  const problems = main(process.argv.slice(2));
  if (problems.length) {
    console.error(`\nShipped SDK assets do not match this build:\n${problems.map((p) => `  - ${p}`).join('\n')}`);
    process.exit(1);
  }
}

module.exports = { describeBundle, main };
