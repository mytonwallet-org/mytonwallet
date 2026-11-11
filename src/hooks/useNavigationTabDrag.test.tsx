import React, { useRef, useState } from '../lib/teact/teact';
import TeactDOM from '../lib/teact/teact-dom';

import type { NavigationTab } from '../global/types';

import { DEFAULT_NAVIGATION_TAB_ORDER, getNavigationTabShift } from '../util/navigationTabOrder';
import { pause } from '../util/schedulers';
import useNavigationTabDrag, { NAVIGATION_TAB_HOLD_DURATION_MS } from './useNavigationTabDrag';

const TAB_HEIGHT_PX = 48;

describe('useNavigationTabDrag', () => {
  let root: HTMLDivElement;
  let onReorder: jest.Mock;
  let onOpen: jest.Mock;
  const offsetTopDescriptor = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'offsetTop')!;
  const { setPointerCapture } = Element.prototype;

  function Bar() {
    const rootRef = useRef<HTMLDivElement>();
    const [order, setOrder] = useState(DEFAULT_NAVIGATION_TAB_ORDER);
    const { drag, consumeDragEndClick, pointerHandlers } = useNavigationTabDrag({
      rootRef,
      tabClassName: 'tab',
      axis: 'y',
      order,
      onReorder: (newOrder) => {
        onReorder(newOrder);
        setOrder(newOrder);
      },
    });

    return (
      <div ref={rootRef} {...pointerHandlers}>
        {order.map((tab, index) => (
          <button
            key={tab}
            className="tab"
            data-tab={tab}
            data-shift={getNavigationTabShift(index, drag)}
            onClick={() => {
              if (!consumeDragEndClick()) onOpen(tab);
            }}
          >
            {tab}
          </button>
        ))}
      </div>
    );
  }

  beforeEach(async () => {
    // The tabs stack in rows, which jsdom does not lay out
    Object.defineProperty(HTMLElement.prototype, 'offsetTop', {
      configurable: true,
      get(this: HTMLElement) {
        return this.parentElement ? Array.from(this.parentElement.children).indexOf(this) * TAB_HEIGHT_PX : 0;
      },
    });
    Element.prototype.setPointerCapture = jest.fn();
    onReorder = jest.fn();
    onOpen = jest.fn();
    root = document.createElement('div');
    document.body.appendChild(root);
    TeactDOM.render(<Bar />, root);
    await pause(20);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    Object.defineProperty(HTMLElement.prototype, 'offsetTop', offsetTopDescriptor);
    Element.prototype.setPointerCapture = setPointerCapture;
  });

  function getTab(tab: NavigationTab) {
    return root.querySelector<HTMLElement>(`[data-tab="${tab}"]`)!;
  }

  function getShifts() {
    return DEFAULT_NAVIGATION_TAB_ORDER.map((tab) => Number(getTab(tab).dataset.shift));
  }

  // Moves keep the button pressed unless told otherwise, as between a press and its release
  function dispatchPointerNow(target: Element, type: string, clientY: number, isPressed = type === 'pointermove') {
    const event = new MouseEvent(type, {
      bubbles: true, cancelable: true, clientX: 10, clientY, button: 0, buttons: isPressed ? 1 : 0,
    });
    target.dispatchEvent(Object.assign(event, { pointerId: 1 }));
  }

  async function dispatchPointer(target: Element, type: string, clientY: number, isPressed?: boolean) {
    dispatchPointerNow(target, type, clientY, isPressed);
    await pause(20);
  }

  it('lifts a tab held still, makes room as it is dragged and saves the order without opening it', async () => {
    const market = getTab('market');
    await dispatchPointer(market, 'pointerdown', 60);
    await pause(NAVIGATION_TAB_HOLD_DURATION_MS + 50);
    await dispatchPointer(market, 'pointermove', 161);

    expect(getShifts()).toEqual([0, 101, -TAB_HEIGHT_PX, -TAB_HEIGHT_PX, 0]);

    await dispatchPointer(market, 'pointerup', 161);
    market.click();

    expect(onReorder).toHaveBeenCalledWith(['wallet', 'agent', 'explore', 'market', 'settings']);
    expect(onOpen).not.toHaveBeenCalled();
    expect(getShifts()).toEqual([0, 0, 0, 0, 0]);
    expect(Array.from(root.querySelectorAll<HTMLElement>('.tab')).map(({ dataset }) => dataset.tab))
      .toEqual(['wallet', 'agent', 'explore', 'market', 'settings']);

    const wallet = getTab('wallet');
    await dispatchPointer(wallet, 'pointerdown', 10);
    await dispatchPointer(wallet, 'pointerup', 10);
    wallet.click();

    expect(onOpen).toHaveBeenCalledWith('wallet');
  });

  it('takes a tab to the first place however far the pointer goes', async () => {
    const settings = getTab('settings');
    await dispatchPointer(settings, 'pointerdown', 200);
    await pause(NAVIGATION_TAB_HOLD_DURATION_MS + 50);
    await dispatchPointer(settings, 'pointermove', -800);
    await dispatchPointer(settings, 'pointerup', -800);

    expect(onReorder).toHaveBeenCalledWith(['settings', 'wallet', 'market', 'agent', 'explore']);
  });

  it('leaves every tab in place for a pointer moving on with no button pressed after the drop', async () => {
    const market = getTab('market');
    await dispatchPointer(market, 'pointerdown', 60);
    await pause(NAVIGATION_TAB_HOLD_DURATION_MS + 50);
    await dispatchPointer(market, 'pointermove', 161);
    // The mouse moves on before the bar renders the drop, when the tab taking the dropped one's place has its index
    dispatchPointerNow(market, 'pointerup', 161);
    dispatchPointerNow(market, 'pointermove', 170, false);
    await pause(20);
    await dispatchPointer(market, 'pointermove', 40, false);

    expect(onReorder).toHaveBeenCalledTimes(1);
    expect(getShifts()).toEqual([0, 0, 0, 0, 0]);
  });

  it('drops a tab whose release the bar did not see once the pointer moves with no button pressed', async () => {
    const market = getTab('market');
    await dispatchPointer(market, 'pointerdown', 60);
    await pause(NAVIGATION_TAB_HOLD_DURATION_MS + 50);
    await dispatchPointer(market, 'pointermove', 161);
    await dispatchPointer(market, 'pointermove', 200, false);
    await dispatchPointer(market, 'pointermove', 10, false);

    expect(onReorder).toHaveBeenCalledWith(['wallet', 'agent', 'explore', 'market', 'settings']);
    expect(getShifts()).toEqual([0, 0, 0, 0, 0]);
  });

  it('never lifts a tab for a mouse that leaves the bar before the hold ends', async () => {
    const market = getTab('market');
    await dispatchPointer(market, 'pointerdown', 60);
    root.querySelector('div')!.dispatchEvent(new MouseEvent('mouseleave'));
    await pause(NAVIGATION_TAB_HOLD_DURATION_MS + 50);
    await dispatchPointer(market, 'pointermove', 161);

    expect(Element.prototype.setPointerCapture).not.toHaveBeenCalled();
    expect(getShifts()).toEqual([0, 0, 0, 0, 0]);
  });

  it('never lifts a tab whose pointer was let go where the bar did not see it', async () => {
    jest.mocked(Element.prototype.setPointerCapture).mockImplementation(() => {
      throw new DOMException('No active pointer', 'NotFoundError');
    });
    const market = getTab('market');
    await dispatchPointer(market, 'pointerdown', 60);
    await pause(NAVIGATION_TAB_HOLD_DURATION_MS + 50);
    await dispatchPointer(market, 'pointermove', 161);

    expect(getShifts()).toEqual([0, 0, 0, 0, 0]);
    expect(onReorder).not.toHaveBeenCalled();
  });

  it('never lifts a tab for a pointer that moves before the hold ends', async () => {
    const wallet = getTab('wallet');
    await dispatchPointer(wallet, 'pointerdown', 10);
    await dispatchPointer(wallet, 'pointermove', 20);
    await pause(NAVIGATION_TAB_HOLD_DURATION_MS + 50);
    await dispatchPointer(wallet, 'pointermove', 110);

    expect(getShifts()).toEqual([0, 0, 0, 0, 0]);

    await dispatchPointer(wallet, 'pointerup', 110);
    wallet.click();

    expect(onReorder).not.toHaveBeenCalled();
    expect(onOpen).toHaveBeenCalledWith('wallet');
  });
});
