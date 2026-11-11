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

    expect(renderFinishedMarkdown(text, true, 'Copy')).toBe(`<p>${text}</p>`);
    expect(renderFinishedMarkdown(text, true, 'Copy')).toBe(`<p>${text}</p>`);
    expect(renderMock).toHaveBeenCalledTimes(1);
  });

  it('keeps an answer with links apart from the same answer without them', () => {
    const text = 'See [the explorer](https://tonscan.org/)';

    expect(renderFinishedMarkdown(text, true, 'Copy')).toBe(`<p>${text}</p>`);
    expect(renderFinishedMarkdown(text, false, 'Copy')).toBe(`<p>${text}</p><!-- no links -->`);
    expect(renderMock).toHaveBeenCalledTimes(2);
  });

  it('renders an answer again for another language\'s Copy label', () => {
    const text = '```\nnpm test\n```';

    renderFinishedMarkdown(text, true, 'Copy');
    renderFinishedMarkdown(text, true, 'Kopieren');
    expect(renderMock).toHaveBeenCalledTimes(2);
    expect(renderMock).toHaveBeenLastCalledWith(text, { areLinksEnabled: true, codeCopyLabel: 'Kopieren' });
  });

  it('drops the answer used longest ago once it holds as many as it keeps', () => {
    renderFinishedMarkdown('Answer 0', true, 'Copy');
    for (let i = 1; i < CACHE_SIZE; i++) {
      renderFinishedMarkdown(`Answer ${i}`, true, 'Copy');
    }
    // Using the first answer again keeps it over the second
    renderFinishedMarkdown('Answer 0', true, 'Copy');
    renderFinishedMarkdown(`Answer ${CACHE_SIZE}`, true, 'Copy');
    renderMock.mockClear();

    renderFinishedMarkdown('Answer 0', true, 'Copy');
    expect(renderMock).not.toHaveBeenCalled();
    renderFinishedMarkdown('Answer 1', true, 'Copy');
    expect(renderMock).toHaveBeenCalledTimes(1);
  });
});
