import { exportLogs } from './logsExport';

const EVIDENCE = { at: '2026-10-10T08:00:00.000Z', keyvalStore: 'absent', enclave: 'absent' };
const mockSaved: string[] = [];
const mockCallApi = jest.fn(() => Promise.resolve([]));

jest.mock('../../api', () => ({
  callApi: () => mockCallApi(),
}));
jest.mock('../../util/indexedDbLoss', () => ({
  getIndexedDbLossEvidence: () => EVIDENCE,
}));
jest.mock('../../util/share', () => ({
  shareFile: (_name: string, content: string) => {
    mockSaved.push(content);
    return Promise.resolve();
  },
}));
jest.mock('../../util/clipboard', () => ({
  copyTextToClipboard: (content: string) => {
    mockSaved.push(content);
    return Promise.resolve();
  },
}));

describe('exportLogs', () => {
  beforeEach(() => {
    mockSaved.length = 0;
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('carries the storage loss evidence whatever the log buffer still holds', async () => {
    await exportLogs({});

    expect(mockSaved).toHaveLength(1);
    const exported = JSON.parse(mockSaved[0]);
    expect(exported).toMatchObject({ storageLossEvidence: EVIDENCE, logs: [] });
    expect(exported).not.toHaveProperty('apiLogsTimedOut');
  });

  it('exports without the worker logs when the worker never answers', async () => {
    jest.useFakeTimers();
    mockCallApi.mockReturnValueOnce(new Promise(() => {}));

    const exportPromise = exportLogs({});
    await jest.runAllTimersAsync();
    await exportPromise;

    expect(mockSaved).toHaveLength(1);
    expect(JSON.parse(mockSaved[0])).toMatchObject({ storageLossEvidence: EVIDENCE, apiLogsTimedOut: true });
  });
});
