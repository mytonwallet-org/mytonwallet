import './domains';
import '../ui/domains';

import type { GlobalState } from '../../types';
import { DomainLinkingState } from '../../types';

import { callApi } from '../../../api';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';

jest.mock('../../../api', () => ({
  callApi: jest.fn(),
}));

describe('updateDomainLinkingMfaRequestStatus', () => {
  // The real handler lives in an action module this test does not load
  const showToast = jest.fn();
  addActionHandler('showToast', showToast);

  beforeEach(() => {
    showToast.mockClear();
    (callApi as jest.Mock).mockResolvedValue({ isConfirmed: true });
  });

  it.each([
    ['linking', false, 'Domain Linked'],
    ['unlinking', true, 'Domain Unlinked'],
  ])('closes the modal with a toast once the %s is confirmed', async (_, isUnlinking, message) => {
    setDomainLinking({ isUnlinking });

    await updateDomainLinkingMfaRequestStatus();

    expect(getGlobal().currentDomainLinking).toEqual({ state: DomainLinkingState.None });
    expect(showToast).toHaveBeenCalledWith(expect.anything(), expect.anything(), { message, icon: 'icon-check' });
  });

  it('keeps the modal open while the MFA request waits for confirmation', async () => {
    setDomainLinking({});
    (callApi as jest.Mock).mockResolvedValue({ isConfirmed: false });

    await updateDomainLinkingMfaRequestStatus();

    expect(getGlobal().currentDomainLinking.state).toBe(DomainLinkingState.ConfirmMfa);
    expect(showToast).not.toHaveBeenCalled();
  });

  it('ignores a confirmation that arrives after the modal is closed', async () => {
    setDomainLinking({});
    (callApi as jest.Mock).mockImplementation(() => {
      getActions().cancelDomainLinking();
      return Promise.resolve({ isConfirmed: true });
    });

    await updateDomainLinkingMfaRequestStatus();

    expect(showToast).not.toHaveBeenCalled();
  });

  function setDomainLinking(update: Partial<GlobalState['currentDomainLinking']>) {
    setGlobal({
      ...getGlobal(),
      currentDomainLinking: {
        state: DomainLinkingState.ConfirmMfa,
        address: 'EQ-domain',
        mfaRequestHash: 'mfa-hash',
        ...update,
      },
    });
  }

  function updateDomainLinkingMfaRequestStatus() {
    return getActions().updateDomainLinkingMfaRequestStatus() as unknown as Promise<void>;
  }
});
