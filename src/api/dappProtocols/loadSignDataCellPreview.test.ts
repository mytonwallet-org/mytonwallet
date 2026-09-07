import type { ApiParsedSignDataCellPreview } from './signDataCellPreview';

import { loadSignDataCellPreview } from './loadSignDataCellPreview';

const PREVIEW: ApiParsedSignDataCellPreview = {
  title: 'Root',
  bits: 8,
  refs: 0,
  fields: [],
  isParsed: true,
};

describe('loadSignDataCellPreview', () => {
  it('loads and builds the cell preview on demand', async () => {
    const buildSignDataCellPreview = jest.fn(() => PREVIEW);
    const loadModule = jest.fn(() => Promise.resolve({ buildSignDataCellPreview }));

    await expect(loadSignDataCellPreview('cell', 'schema', loadModule)).resolves.toBe(PREVIEW);
    expect(loadModule).toHaveBeenCalledTimes(1);
    expect(buildSignDataCellPreview).toHaveBeenCalledWith('cell', 'schema');
  });

  it('returns no preview when the parser chunk fails to load', async () => {
    const loadModule = jest.fn(() => Promise.reject(new Error('ChunkLoadError')));

    await expect(loadSignDataCellPreview('cell', 'schema', loadModule)).resolves.toBeUndefined();
  });

  it('returns no preview when preview parsing throws unexpectedly', async () => {
    const loadModule = jest.fn(() => Promise.resolve({
      buildSignDataCellPreview: () => {
        throw new Error('parser failed');
      },
    }));

    await expect(loadSignDataCellPreview('cell', 'schema', loadModule)).resolves.toBeUndefined();
  });
});
