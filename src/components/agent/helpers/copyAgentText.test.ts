import { copyTextToClipboard } from '../../../util/clipboard';
import { copyAgentText } from './copyAgentText';

const mockShowToast = jest.fn();

// The test setup seeds the global state through `setGlobal`
jest.mock('../../../global', () => ({ getActions: () => ({ showToast: mockShowToast }), setGlobal: jest.fn() }));
jest.mock('../../../util/clipboard', () => ({ copyTextToClipboard: jest.fn() }));
jest.mock('../../../util/langProvider', () => ({ getTranslation: (key: string) => `[${key}]` }));

const copyMock = jest.mocked(copyTextToClipboard);

describe('copyAgentText', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('says so in a toast once the clipboard holds the text', async () => {
    let resolveCopy!: NoneToVoidFunction;
    copyMock.mockReturnValue(new Promise<void>((resolve) => {
      resolveCopy = resolve;
    }));

    const copying = copyAgentText('TON is up 3%');
    await Promise.resolve();
    expect(copyMock).toHaveBeenCalledWith('TON is up 3%');
    expect(mockShowToast).not.toHaveBeenCalled();

    resolveCopy();
    await copying;
    expect(mockShowToast).toHaveBeenCalledWith({ message: '[Message Copied]', icon: 'icon-copy' });
  });

  it('shows no toast when the clipboard refuses the text', async () => {
    copyMock.mockRejectedValue(new Error('Document is not focused'));

    await expect(copyAgentText('TON is up 3%')).rejects.toThrow('Document is not focused');
    expect(mockShowToast).not.toHaveBeenCalled();
  });

  it('names what was copied with the text it is given', async () => {
    copyMock.mockResolvedValue(undefined);

    await copyAgentText('Today 9:41', 'Copied');
    expect(mockShowToast).toHaveBeenCalledWith({ message: '[Copied]', icon: 'icon-copy' });
  });
});
