import {
  addChunkLoadErrorListener,
  createChunkLoader,
  handleChunkLoadError,
  isChunkLoadError,
  reportApiChunkLoadError,
} from './chunkLoading';

const CHROMIUM_ERROR = new TypeError('Failed to fetch dynamically imported module: https://x.io/chart.OLD.js');
const FIREFOX_ERROR = new TypeError('error loading dynamically imported module: https://x.io/chart.OLD.js');
const SAFARI_ERROR = new TypeError('Importing a module script failed.');
const VITE_CSS_ERROR = new Error('Unable to preload CSS for ./chart.OLD.css');
const EVALUATION_ERROR = new TypeError('Cannot read properties of undefined (reading \'init\')');

describe('isChunkLoadError', () => {
  it.each([CHROMIUM_ERROR, FIREFOX_ERROR, SAFARI_ERROR, VITE_CSS_ERROR])('recognizes %s', (err) => {
    expect(isChunkLoadError(err)).toBe(true);
  });

  it('does not take an error thrown by the module itself for a failed load', () => {
    expect(isChunkLoadError(EVALUATION_ERROR)).toBe(false);
    expect(isChunkLoadError('Failed to fetch dynamically imported module')).toBe(false);
    expect(isChunkLoadError(undefined)).toBe(false);
  });
});

describe('createChunkLoader', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('loads a chunk once', async () => {
    const load = jest.fn(() => Promise.resolve('module'));
    const loadChunk = createChunkLoader(load);

    await expect(loadChunk()).resolves.toBe('module');
    await expect(loadChunk()).resolves.toBe('module');
    expect(load).toHaveBeenCalledTimes(1);
  });

  it('shares a failed load for a while and then loads again', async () => {
    const load = jest.fn()
      .mockRejectedValueOnce(CHROMIUM_ERROR)
      .mockResolvedValueOnce('module');
    const loadChunk = createChunkLoader(load);

    await expect(loadChunk()).rejects.toBe(CHROMIUM_ERROR);
    await expect(loadChunk()).rejects.toBe(CHROMIUM_ERROR);
    expect(load).toHaveBeenCalledTimes(1);

    jest.runAllTimers();

    await expect(loadChunk()).resolves.toBe('module');
    expect(load).toHaveBeenCalledTimes(2);
  });
});

describe('handleChunkLoadError', () => {
  it('absorbs a failed load', () => {
    expect(() => handleChunkLoadError('test')(FIREFOX_ERROR)).not.toThrow();
  });

  it('rethrows an error thrown by the module itself', () => {
    expect(() => handleChunkLoadError('test')(EVALUATION_ERROR)).toThrow(EVALUATION_ERROR);
  });
});

describe('chunk load error events', () => {
  const callback = jest.fn();

  beforeAll(() => {
    addChunkLoadErrorListener(callback);
  });

  beforeEach(() => {
    callback.mockClear();
  });

  it('reports a failed chunk import on the main thread', () => {
    window.dispatchEvent(Object.assign(new Event('vite:preloadError'), { payload: CHROMIUM_ERROR }));
    expect(callback).toHaveBeenCalledTimes(1);
  });

  it('ignores a module that failed while evaluating', () => {
    window.dispatchEvent(Object.assign(new Event('vite:preloadError'), { payload: EVALUATION_ERROR }));
    expect(callback).not.toHaveBeenCalled();
  });

  it('reports a failed chunk import in the API worker', () => {
    reportApiChunkLoadError(new Error(FIREFOX_ERROR.message));
    reportApiChunkLoadError(new Error('Ledger is disabled'));
    expect(callback).toHaveBeenCalledTimes(1);
  });
});
