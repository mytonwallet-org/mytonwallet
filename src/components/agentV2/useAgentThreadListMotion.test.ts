import React, { useRef, type VirtualElementComponent } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';

import {
  disableStrict, enableStrict, setHandler, setPhase,
} from '../../lib/fasterdom/fasterdom';
import { pause } from '../../util/schedulers';
import useAgentThreadListMotion from './useAgentThreadListMotion';

const ROW_HEIGHT = 76;

describe('useAgentThreadListMotion', () => {
  let root: HTMLDivElement;
  let body: HTMLDivElement;
  let rows: HTMLDivElement[];
  const originalScrollTo = Element.prototype.scrollTo;

  function Harness({ items }: { items: AgentThreadListItemV2[] }) {
    const bodyRef = useRef(body);
    useAgentThreadListMotion(bodyRef, items, false);

    return undefined;
  }

  function render(items: AgentThreadListItemV2[]) {
    TeactDOM.render(React.createElement(Harness, { items }) as VirtualElementComponent, root);
  }

  beforeEach(() => {
    root = document.createElement('div');
    body = document.createElement('div');
    rows = ['a', 'b', 'c'].map((key) => {
      const row = document.createElement('div');
      row.setAttribute('data-agent-row-key', key);
      body.appendChild(row);
      return row;
    });
    Object.defineProperties(body, {
      offsetHeight: { configurable: true, value: 3 * ROW_HEIGHT },
      scrollTop: { configurable: true, value: 100 },
    });
    placeRows(0);
    document.body.append(root, body);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    body.remove();
    disableStrict();
    setHandler();
    setPhase('measure');
    Element.prototype.scrollTo = originalScrollTo;
  });

  it('keeps the rows where they were when a chat comes in above them, scrolling in the measure phase', async () => {
    const scrollTo = jest.fn();
    Element.prototype.scrollTo = scrollTo;
    const errors: Error[] = [];
    render(buildItems(3));
    await pause(50);

    setHandler((error) => errors.push(error));
    enableStrict();
    placeRows(ROW_HEIGHT);
    render(buildItems(4));
    await pause(50);

    expect(scrollTo).toHaveBeenCalledWith({ top: 100 + ROW_HEIGHT, behavior: 'instant' });
    expect(errors).toEqual([]);
  });

  function placeRows(offset: number) {
    rows.forEach((row, index) => {
      Object.defineProperties(row, {
        offsetTop: { configurable: true, value: offset + index * ROW_HEIGHT },
        offsetHeight: { configurable: true, value: ROW_HEIGHT },
      });
    });
  }
});

function buildItems(count: number) {
  return Array.from({ length: count }, (_, index) => ({ id: String(index) })) as unknown as AgentThreadListItemV2[];
}
