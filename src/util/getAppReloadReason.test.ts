import getAppReloadReason from './getAppReloadReason';

const RUNNING_COMMIT = '1f6c7b213967c9278360aca074e70b2a6276b0db';

function buildInfo(commit: string) {
  return ['version=26.9.9', `commit=${commit}`, 'branch=master', 'env=staging', ''].join('\n');
}

describe('getAppReloadReason', () => {
  it('reports a new build when the host serves another commit', () => {
    expect(getAppReloadReason(buildInfo('ae05b854512b4b9630919b91831953c94e9a5298'), RUNNING_COMMIT))
      .toBe('buildOutdated');
  });

  it('reports a failed chunk when the host serves the running build', () => {
    expect(getAppReloadReason(buildInfo(RUNNING_COMMIT), RUNNING_COMMIT)).toBe('chunkLoadFailed');
  });

  it('suggests nothing when the host answers with a page instead of `build.txt`', () => {
    expect(getAppReloadReason('<!DOCTYPE html>\n<html lang="en">\n</html>\n', RUNNING_COMMIT)).toBeUndefined();
  });

  it('suggests nothing when the served build has no commit', () => {
    expect(getAppReloadReason('version=26.9.9\nenv=staging\n', RUNNING_COMMIT)).toBeUndefined();
  });
});
