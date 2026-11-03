import type { FC } from '../lib/teact/teact';
import React from '../lib/teact/teact';
import TeactDOM from '../lib/teact/teact-dom';

import type { DialogType } from '../global/types';

import { requestNextMutation } from '../lib/fasterdom/fasterdom';
import { waitFor } from '../util/schedulers';

import Dialogs from './Dialogs';

const mockExportLogs = jest.fn((..._args: unknown[]) => Promise.resolve(false));
const mockCollectLogs = jest.fn(() => Promise.resolve('{}'));
const mockDismissDialog = jest.fn();

jest.mock('../global', () => ({
  ...jest.requireActual('../global'),
  getActions: () => ({ dismissDialog: mockDismissDialog, showToast: jest.fn() }),
  getGlobal: () => ({ accounts: { byId: {} } }),
  withGlobal: () => (Component: unknown) => Component,
}));
jest.mock('../global/helpers/logsExport', () => ({
  ...jest.requireActual('../global/helpers/logsExport'),
  collectLogs: () => mockCollectLogs(),
  exportLogs: (...args: unknown[]) => mockExportLogs(...args),
}));
jest.mock('../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
jest.mock('./ui/Modal', () => {
  const { default: TeactReact } = jest.requireActual('../lib/teact/teact');

  return {
    __esModule: true,
    default: ({ isOpen, children }: { isOpen: boolean; children: unknown }) => (
      isOpen ? TeactReact.createElement('div', { className: 'mock-modal' }, children) : undefined
    ),
  };
});

const DialogsWithState = Dialogs as FC<{ dialogs: DialogType[] }>;

// Resolves after the render pass already queued, so a close the click requested is on screen by then
const flushRender = () => new Promise<void>((resolve) => {
  requestNextMutation(resolve);
});

describe('Dialogs', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.clearAllMocks();
  });

  it('exports the logs and stays open', async () => {
    TeactDOM.render(
      <DialogsWithState dialogs={[{
        message: 'Send the logs to support',
        buttons: { confirm: { action: 'exportLogs' }, cancel: { title: 'Close' } },
      }]}
      />,
      root,
    );
    const getExportButton = () => [...root.querySelectorAll('button')]
      .find((button) => button.textContent === 'Download Logs');
    expect(await waitFor(() => Boolean(getExportButton()), 10, 100)).toBe(true);
    // The share sheet opens only within the click's user activation, so nothing slow may sit between the two
    expect(mockCollectLogs).toHaveBeenCalledTimes(1);

    getExportButton()!.click();
    await flushRender();

    expect(mockExportLogs).toHaveBeenCalledTimes(1);
    expect(mockExportLogs).toHaveBeenCalledWith(expect.anything(), mockCollectLogs.mock.results[0].value);
    expect(root.querySelector('.mock-modal')).not.toBeNull();
  });
});
