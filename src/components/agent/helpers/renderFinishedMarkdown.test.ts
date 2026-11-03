import renderMarkdown from '../../../util/renderMarkdown';
import renderFinishedMarkdown from './renderFinishedMarkdown';

jest.mock('../../../util/renderMarkdown', () => ({
  __esModule: true,
  default: jest.fn((text: string, { areLinksEnabled }: { areLinksEnabled: boolean }) => ({
    html: `<p>${text}</p>${areLinksEnabled ? '' : '<!-- no links -->'}`,
  })),
}));

const CACHE_SIZE = 100;

const renderMock = jest.mocked(renderMarkdown);

describe('renderFinishedMarkdown', () => {
  beforeEach(() => {
    renderMock.mockClear();
  });

  it('parses a finished answer once however often it mounts', () => {
    const text = '**TON** is up 3% this week';

    expect(renderFinishedMarkdown(text, true)).toBe(`<p>${text}</p>`);
    expect(renderFinishedMarkdown(text, true)).toBe(`<p>${text}</p>`);
    expect(renderMock).toHaveBeenCalledTimes(1);
  });

  it('keeps an answer with links apart from the same answer without them', () => {
    const text = 'See [the explorer](https://tonscan.org/)';

    expect(renderFinishedMarkdown(text, true)).toBe(`<p>${text}</p>`);
    expect(renderFinishedMarkdown(text, false)).toBe(`<p>${text}</p><!-- no links -->`);
    expect(renderMock).toHaveBeenCalledTimes(2);
  });

  it('drops the answer used longest ago once it holds as many as it keeps', () => {
    renderFinishedMarkdown('Answer 0', true);
    for (let i = 1; i < CACHE_SIZE; i++) {
      renderFinishedMarkdown(`Answer ${i}`, true);
    }
    // Using the first answer again keeps it over the second
    renderFinishedMarkdown('Answer 0', true);
    renderFinishedMarkdown(`Answer ${CACHE_SIZE}`, true);
    renderMock.mockClear();

    renderFinishedMarkdown('Answer 0', true);
    expect(renderMock).not.toHaveBeenCalled();
    renderFinishedMarkdown('Answer 1', true);
    expect(renderMock).toHaveBeenCalledTimes(1);
  });
});
