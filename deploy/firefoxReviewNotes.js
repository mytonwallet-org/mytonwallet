const fs = require('fs');

const { FIREFOX_REVIEW_NOTES } = process.env;

if (!FIREFOX_REVIEW_NOTES) {
  throw new Error('Missing env vars!');
}

const buildInfo = JSON.parse(fs.readFileSync('MyWallet-firefox-build.json', 'utf8'));

// The notes can carry test-wallet credentials, so they go to a file and never to the job log
process.stdout.write(
  FIREFOX_REVIEW_NOTES
    .replace(/<!--[\s\S]*?-->\n*/g, '')
    .replace(/{{(\w+)}}/g, (_, key) => {
      if (!Object.hasOwn(buildInfo, key)) {
        throw new Error(`The reviewer notes name an unknown build fact: ${key}`);
      }
      return buildInfo[key];
    }),
);
