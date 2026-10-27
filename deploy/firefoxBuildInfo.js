const { execFileSync } = require('child_process');
const fs = require('fs');

const {
  GITHUB_SERVER_URL,
  GITHUB_REPOSITORY,
  GITHUB_RUN_ID,
  GITHUB_SHA,
} = process.env;

if (!GITHUB_SERVER_URL || !GITHUB_REPOSITORY || !GITHUB_RUN_ID || !GITHUB_SHA) {
  throw new Error('Missing env vars!');
}

// Facts about the build this job has just made, which the publish job puts into the reviewer notes
const { version } = JSON.parse(fs.readFileSync('dist/manifest.json', 'utf8'));
const repositoryUrl = `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}`;

process.stdout.write(JSON.stringify({
  version,
  repositoryUrl,
  runUrl: `${repositoryUrl}/actions/runs/${GITHUB_RUN_ID}`,
  commit: GITHUB_SHA,
  os: getOsName(),
  arch: process.arch,
  node: process.version,
  npm: execFileSync('npm', ['--version'], { encoding: 'utf8' }).trim(),
}, undefined, 2));

function getOsName() {
  if (!fs.existsSync('/etc/os-release')) {
    return process.platform;
  }
  const osRelease = fs.readFileSync('/etc/os-release', 'utf8');
  return osRelease.match(/^PRETTY_NAME="?([^"\n]+)"?$/m)?.[1] ?? process.platform;
}
