import './cards';

import type { ActionPayloads, GlobalState } from '../../types';
import { MintCardState } from '../../types';

import { callApi } from '../../../api';
import { addActionHandler } from '../../index';
import { INITIAL_STATE } from '../../initialState';

jest.mock('../../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getActions: jest.fn(() => ({})),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
}));

type CheckMintStartHandler = (
  global: GlobalState,
  actions: object,
  payload: ActionPayloads['checkMintStart'],
) => GlobalState | undefined;

const checkMintStart = jest.mocked(addActionHandler).mock.calls
  .find(([name]) => name === 'checkMintStart')![1] as CheckMintStartHandler;

const STARTS_AT = Date.UTC(2027, 0, 15, 8);
const OPEN_MODAL: GlobalState = { ...INITIAL_STATE, currentMintCard: { state: MintCardState.Initial } };

describe('actions/api/cards', () => {
  describe('checkMintStart', () => {
    beforeEach(() => {
      jest.mocked(callApi).mockClear();
    });

    it('polls the account config once per start time while the modal is open', () => {
      const checked = checkMintStart(OPEN_MODAL, {}, { startsAt: STARTS_AT })!;

      expect(checked.currentMintCard?.checkedMintStartsAt).toBe(STARTS_AT);
      expect(checkMintStart(checked, {}, { startsAt: STARTS_AT })).toBeUndefined();
      expect(callApi).toHaveBeenCalledTimes(1);
      expect(callApi).toHaveBeenCalledWith('pollAccountConfig');

      checkMintStart(checked, {}, { startsAt: STARTS_AT + 1000 });

      expect(callApi).toHaveBeenCalledTimes(2);
    });

    it('does nothing when the modal is closed', () => {
      expect(checkMintStart(INITIAL_STATE, {}, { startsAt: STARTS_AT })).toBeUndefined();
      expect(callApi).not.toHaveBeenCalled();
    });
  });
});
