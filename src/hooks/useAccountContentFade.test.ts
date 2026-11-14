import './useAccountContentFade';

import { addCallback } from '../lib/teact/teactn';

import type { GlobalState } from '../global/types';

import { ANIMATION_LEVEL_MAX, ANIMATION_LEVEL_MIN } from '../config';
import { captureAccountContent } from '../util/accountContentTransition';

jest.mock('../lib/teact/teactn', () => ({ ...jest.requireActual('../lib/teact/teactn'), addCallback: jest.fn() }));
jest.mock('../util/accountContentTransition', () => ({ captureAccountContent: jest.fn() }));

const onGlobalChange = jest.mocked(addCallback).mock.calls[0][0] as (global: GlobalState) => void;

function makeGlobal(currentAccountId: string, animationLevel = ANIMATION_LEVEL_MAX) {
  return { currentAccountId, settings: { animationLevel } } as GlobalState;
}

it('snapshots the screen only when the current account changes', () => {
  onGlobalChange(makeGlobal('0-ton-mainnet'));
  onGlobalChange(makeGlobal('0-ton-mainnet'));
  expect(captureAccountContent).toHaveBeenCalledTimes(1);

  onGlobalChange(makeGlobal('1-ton-mainnet', ANIMATION_LEVEL_MIN));
  expect(captureAccountContent).toHaveBeenCalledTimes(1);

  jest.mocked(captureAccountContent).mockImplementationOnce(() => {
    throw new Error('Canvas without pixels');
  });
  expect(() => onGlobalChange(makeGlobal('2-ton-mainnet'))).not.toThrow();
  expect(captureAccountContent).toHaveBeenCalledTimes(2);
});
