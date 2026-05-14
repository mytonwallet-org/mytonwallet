/* eslint-disable @typescript-eslint/no-require-imports, no-console */

require('@babel/register')({
  extensions: ['.js', '.ts'],
  plugins: ['babel-plugin-transform-import-meta'],
});

const { access, readFile, writeFile } = require('node:fs/promises');
const { setAccountValue } = require('../common/accounts');
const { withStorage } = require('./index');
const { createNodeFileStorage } = require('./nodeFile');

async function waitForFile(filePath) {
  while (true) {
    try {
      await access(filePath);
      return;
    } catch (err) {
      if (err && err.code !== 'ENOENT') {
        throw err;
      }

      await new Promise((resolve) => setTimeout(resolve, 10));
    }
  }
}

async function main() {
  const [storagePath, readyPath, startPath, targetKey, payloadJson, accountId] = process.argv.slice(2);

  if (!storagePath || !readyPath || !startPath || !targetKey || !payloadJson) {
    throw new Error('Missing writer arguments');
  }

  const storage = createNodeFileStorage({ type: 'nodeFile', path: storagePath });

  await writeFile(readyPath, 'ready', 'utf8');
  await waitForFile(startPath);

  if (targetKey === '__setAccountValue__') {
    await withStorage(storage, () => setAccountValue(accountId, 'accounts', JSON.parse(payloadJson)));
  } else {
    await storage.setItem(targetKey, JSON.parse(payloadJson));
  }

  const stored = await readFile(storagePath, 'utf8');
  process.stdout.write(stored);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
