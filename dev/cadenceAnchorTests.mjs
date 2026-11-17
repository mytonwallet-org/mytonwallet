import assert from 'node:assert/strict';
import test from 'node:test';

import { moveAnchor } from './cadenceAnchor.mjs';

const RUN_SHA = 'b'.repeat(40);
const ANCHOR_SHA = 'a'.repeat(40);

test('an anchor behind this run moves to it with a bot-signed annotated tag', async () => {
  const github = makeGithub({ statuses: { [`${ANCHOR_SHA}...${RUN_SHA}`]: 'ahead' } });
  assert.equal(await moveAnchor(makeArgs(github)), 'moved');
  const created = findCall(github, 'createTag');
  assert.equal(created.tag, 'cadence-anchor-ios-mywallet');
  assert.equal(created.object, RUN_SHA);
  assert.equal(created.tagger.name, 'github-actions[bot]');
  assert.deepEqual(findCall(github, 'updateRef'), { owner: 'o', repo: 'r', ref: 'tags/cadence-anchor-ios-mywallet', sha: 'tag-object', force: true });
});

test('an anchor at or ahead of this run stays where it is', async () => {
  for (const status of ['identical', 'behind']) {
    const github = makeGithub({ statuses: { [`${ANCHOR_SHA}...${RUN_SHA}`]: status } });
    assert.equal(await moveAnchor(makeArgs(github)), 'kept');
    assert.equal(github.calls.some((call) => call.name === 'createTag'), false);
  }
});

test('an anchor master no longer holds is replaced while this run is still on master', async () => {
  const github = makeGithub({
    statuses: { [`${ANCHOR_SHA}...${RUN_SHA}`]: 'diverged', [`${RUN_SHA}...tip`]: 'ahead' },
  });
  assert.equal(await moveAnchor(makeArgs(github)), 'moved');
});

test('a diverged anchor stays when this run left master too', async () => {
  const github = makeGithub({
    statuses: { [`${ANCHOR_SHA}...${RUN_SHA}`]: 'diverged', [`${RUN_SHA}...tip`]: 'diverged' },
  });
  assert.equal(await moveAnchor(makeArgs(github)), 'kept');
});

test('a missing anchor is created, and a missing ref after the tag object is created too', async () => {
  const github = makeGithub({ anchorMissing: true, updateStatus: 404 });
  assert.equal(await moveAnchor(makeArgs(github)), 'moved');
  assert.deepEqual(findCall(github, 'createRef'), { owner: 'o', repo: 'r', ref: 'refs/tags/cadence-anchor-ios-mywallet', sha: 'tag-object' });
});

test('any other error reading the anchor fails the step', async () => {
  const github = makeGithub({ anchorError: 500 });
  await assert.rejects(moveAnchor(makeArgs(github)), /boom/);
});

function makeArgs(github) {
  return {
    github,
    context: { sha: RUN_SHA, repo: { owner: 'o', repo: 'r' } },
    core: { warning: () => {}, info: () => {} },
    key: 'ios-mywallet',
  };
}

function makeGithub({ statuses = {}, anchorMissing = false, anchorError, updateStatus }) {
  const calls = [];
  const record = (name, params) => calls.push({ name, params });
  const fail = (status) => Object.assign(new Error('boom'), { status });
  return {
    calls,
    rest: {
      git: {
        getRef: async (params) => {
          record('getRef', params);
          if (anchorError) throw fail(anchorError);
          if (anchorMissing) throw fail(404);
          return { data: { object: { sha: 'anchor-tag' } } };
        },
        getTag: async () => ({ data: { object: { sha: ANCHOR_SHA } } }),
        createTag: async (params) => {
          record('createTag', params);
          return { data: { sha: 'tag-object' } };
        },
        updateRef: async (params) => {
          record('updateRef', params);
          if (updateStatus) throw fail(updateStatus);
        },
        createRef: async (params) => record('createRef', params),
      },
      repos: {
        getBranch: async () => ({ data: { commit: { sha: 'tip' } } }),
        compareCommits: async ({ base, head }) => ({ data: { status: statuses[`${base}...${head}`] } }),
      },
    },
  };
}

function findCall(github, name) {
  return github.calls.find((call) => call.name === name).params;
}
