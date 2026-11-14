import getAgentHeaderBottom from './getAgentHeaderBottom';

describe('getAgentHeaderBottom', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('finds the lowest edge of the Agent headers over a span, leaving out those beside it and hidden ones', () => {
    addHeader({ left: 0, width: 400, bottom: 48 });
    // The header of a chat that slides in over the feed
    addHeader({ left: 200, width: 400, bottom: 56 });
    addHeader({ left: 500, width: 400, bottom: 80 });
    addHeader({ left: 0, width: 0, bottom: 120 });

    expect(getAgentHeaderBottom(100, 300)).toBe(56);
    expect(getAgentHeaderBottom(0, 150)).toBe(48);
    expect(getAgentHeaderBottom(950, 1000)).toBeUndefined();

    // What is attached under a header, as the news feed's view switch, ends it lower
    addHeader({ left: 0, width: 400, bottom: 94 }, 'data-agent-header-accessory');
    expect(getAgentHeaderBottom(0, 150)).toBe(94);
  });
});

function addHeader(
  { left, width, bottom }: { left: number; width: number; bottom: number }, attribute = 'data-agent-header',
) {
  const header = document.createElement('div');
  header.setAttribute(attribute, '');
  header.getBoundingClientRect = () => ({
    left, right: left + width, width, top: 0, bottom, height: bottom, x: left, y: 0, toJSON: () => undefined,
  });
  document.body.appendChild(header);
}
