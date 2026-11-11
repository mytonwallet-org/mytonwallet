import { DESIGN_PIXEL, getAgentDictationLockProgress } from './AgentDictationCircle';

describe('getAgentDictationLockProgress', () => {
  it('closes the lock in proportion to the finger sliding up, shut at the lock', () => {
    const travels = [0, 20, 52.5, 80, 105].map((travel) => -travel * DESIGN_PIXEL);
    const progresses = travels.map(getAgentDictationLockProgress);

    expect(progresses[0]).toBe(0);
    expect(progresses[2]).toBeCloseTo(0.5);
    expect(progresses[4]).toBe(1);
    progresses.slice(1).forEach((progress, index) => {
      expect(progress).toBeGreaterThan(progresses[index]);
    });
  });

  it('keeps a finger past the lock at the lock', () => {
    expect(getAgentDictationLockProgress(-160 * DESIGN_PIXEL)).toBe(1);
  });
});
