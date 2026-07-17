const jwt = require('jsonwebtoken');
const fs = require('fs');

const {
  WEB_EXT_API_KEY,
  WEB_EXT_API_SECRET,
  FIREFOX_EXTENSION_ID,
} = process.env;

if (!WEB_EXT_API_KEY || !WEB_EXT_API_SECRET || !FIREFOX_EXTENSION_ID) {
  throw new Error('Missing env vars!');
}

const extId = FIREFOX_EXTENSION_ID;
const baseUrl = 'https://addons.mozilla.org';
const sourceFile = 'MyWallet-firefox-sources.tgz';

const token = getAuthToken(WEB_EXT_API_KEY, WEB_EXT_API_SECRET);
const headers = { Authorization: `JWT ${token}` };

async function main() {
  const { lastId, approvalNotes } = await getLastVersionsInfo();

  console.log('Version ID:', lastId);
  console.log('Approval notes:', approvalNotes);

  await uploadSource(lastId);
  await uploadApprovalNotes(lastId, approvalNotes);
}

function getAuthToken(key, secret) {
  const issuedAt = Math.floor(Date.now() / 1000);
  const payload = {
    iss: key,
    jti: Math.random().toString(),
    iat: issuedAt,
    exp: issuedAt + 60,
  };

  return jwt.sign(payload, secret, {
    algorithm: 'HS256',
  });
}

async function getLastVersionsInfo() {
  const res = await fetch(`${baseUrl}/api/v5/addons/addon/${extId}/versions/?filter=all_with_unlisted`, {
    method: 'GET',
    headers,
  });
  handleFetchErrors(res);
  const { results } = await res.json();

  const lastId = results[0].id;
  let approvalNotes = '';
  for (const version of results) {
    if (version.approval_notes) {
      approvalNotes = version.approval_notes;
      break;
    }
  }

  return { lastId, approvalNotes }
}

async function uploadSource(versionId) {
  const blob = new Blob(
    [await fs.promises.readFile(sourceFile)],
    { type: 'application/octet-stream' },
  );

  const form = new FormData();
  form.append('source', blob, sourceFile);

  const res = await fetch(`${baseUrl}/api/v5/addons/addon/${extId}/versions/${versionId}/`, {
    method: 'PATCH',
    body: form,
    headers,
  });
  handleFetchErrors(res);
}

async function uploadApprovalNotes(versionId, approvalNotes) {
  const res = await fetch(`${baseUrl}/api/v5/addons/addon/${extId}/versions/${versionId}/`, {
    method: 'PATCH',
    body: JSON.stringify({
      approval_notes: approvalNotes,
    }),
    headers: {
      ...headers,
      'Content-Type': 'application/json',
    },
  });
  handleFetchErrors(res);
}

function handleFetchErrors(response) {
  if (!response.ok) {
    response.json().then(console.error);
    throw new Error(response.statusText);
  }
  return response;
}

void main();
