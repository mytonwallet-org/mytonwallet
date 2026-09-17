import type { ApiActivity } from '../../api/types';
import type { AccountState } from '../types';

import { resolveReplacedActivityId } from './misc';

function makeActivities(
  ids: string[],
  activityIdReplacements?: Record<string, string>,
): AccountState['activities'] {
  return {
    byId: Object.fromEntries(ids.map((id) => [id, { id } as ApiActivity])),
    activityIdReplacements,
  };
}

describe('resolveReplacedActivityId', () => {
  it('keeps an id that is present in `byId`', () => {
    const activities = makeActivities(['local', 'chain'], { local: 'chain' });

    expect(resolveReplacedActivityId(activities, 'local')).toBe('local');
  });

  it('follows a chain of replacements to the id that is present in `byId`', () => {
    const activities = makeActivities(['aggregate'], { local: 'backend', backend: 'aggregate' });

    expect(resolveReplacedActivityId(activities, 'local')).toBe('aggregate');
  });

  it('returns the last id of a chain that leads nowhere', () => {
    const activities = makeActivities([], { local: 'backend' });

    expect(resolveReplacedActivityId(activities, 'local')).toBe('backend');
  });

  it('stops on a replacement cycle', () => {
    const activities = makeActivities([], { first: 'second', second: 'first' });

    expect(resolveReplacedActivityId(activities, 'first')).toBe('first');
  });

  it('returns the id when there are no activities', () => {
    expect(resolveReplacedActivityId(undefined, 'local')).toBe('local');
  });
});
