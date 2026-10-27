import { getLogs } from '../../../../util/logs';
import { logDeploymentStateDrift } from './deploymentStateDrift';

const MESSAGE = 'The stored wallet deployment state disagrees with the chain';

function countDriftLogs() {
  return getLogs().filter(({ message }) => message === MESSAGE).length;
}

describe('logDeploymentStateDrift', () => {
  it('reports a wallet stored as deployed that the chain does not call active', () => {
    const before = countDriftLogs();

    logDeploymentStateDrift(`address-${Math.random()}`, true, false);

    expect(countDriftLogs()).toBe(before + 1);
  });

  it('stays silent while the stored state and the chain agree', () => {
    const before = countDriftLogs();

    logDeploymentStateDrift(`address-${Math.random()}`, true, true);
    logDeploymentStateDrift(`address-${Math.random()}`, false, false);
    logDeploymentStateDrift(`address-${Math.random()}`, undefined, false);
    logDeploymentStateDrift(`address-${Math.random()}`, undefined, true);

    expect(countDriftLogs()).toBe(before);
  });
});
