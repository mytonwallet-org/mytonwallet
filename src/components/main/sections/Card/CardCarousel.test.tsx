import React from '../../../../lib/teact/teact';
import TeactDOM from '../../../../lib/teact/teact-dom';

import type { Account } from '../../../../global/types';

import { preloadCardArtworks } from '../../../../hooks/useCardArtwork';

import CardCarousel from './CardCarousel';

const CARD_STEP_PX = 308;
const ACCOUNT_IDS = ['first', 'second', 'third', 'fourth', 'fifth'];

let mockAccountId = 'first';
let mockShownAccountId: string | undefined;
let isMotionDisabled = false;
const mockSettingsByAccountId = Object.fromEntries(
  ACCOUNT_IDS.map((id) => [id, { cardBackgroundNft: { address: id } }]),
);
const mockShowCardAccount = jest.fn();
const mockSwitchToCardAccount = jest.fn();
const mockRenderCard = jest.fn();
const mockCardLayoutEffect = jest.fn();
const mockHandleYieldClick = jest.fn();

jest.mock('../../../../global', () => ({
  setGlobal: jest.fn(),
  getGlobal: () => ({
    currentAccountId: mockAccountId,
    shownCardAccountId: mockShownAccountId,
    settings: { byAccountId: mockSettingsByAccountId },
  }),
  getActions: () => ({ showCardAccount: mockShowCardAccount, switchToCardAccount: mockSwitchToCardAccount }),
  withGlobal: () => (component: unknown) => component,
}));
jest.mock('../../../../global/selectors', () => ({
  selectCurrentAccountId: (global: { currentAccountId: string }) => global.currentAccountId,
  selectShownCardAccountId: (global: { currentAccountId: string; shownCardAccountId?: string }) => (
    global.shownCardAccountId ?? global.currentAccountId
  ),
}));
jest.mock('../../../../util/windowEnvironment', () => ({
  ...jest.requireActual('../../../../util/windowEnvironment'),
  REM: 16,
}));
jest.mock('../../../../hooks/useCardArtwork', () => ({ preloadCardArtworks: jest.fn() }));
jest.mock('../../../../hooks/useDeviceScreen', () => ({ useDeviceScreen: () => ({ isPortrait: false }) }));
jest.mock('../../../../hooks/useLang', () => ({ __esModule: true, default: () => (key: string) => key }));
jest.mock('./Card', () => {
  const { useLayoutEffect } = jest.requireActual('../../../../lib/teact/teact');

  return {
    __esModule: true,
    default: (props: unknown) => {
      const content = mockRenderCard(props);

      useLayoutEffect(() => {
        mockCardLayoutEffect(mockGetCarouselCardWidth());
      }, []);

      return content;
    },
  };
});

let root: HTMLDivElement;
let viewport: HTMLDivElement;

beforeEach(() => {
  jest.useFakeTimers();
  jest.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(300);
  mockAccountId = 'first';
  mockShownAccountId = undefined;
  isMotionDisabled = false;
  mockRenderCard.mockReset();
  mockCardLayoutEffect.mockReset();
  mockShowCardAccount.mockReset();
  mockShowCardAccount.mockImplementation(({ accountId }: { accountId: string }) => {
    if (mockShownAccountId === undefined && accountId === mockAccountId) return;

    mockShownAccountId = accountId;
    renderCarouselWithGlobal();
  });
  mockSwitchToCardAccount.mockReset();
  mockSwitchToCardAccount.mockImplementation(({ accountId }: { accountId: string }) => {
    mockAccountId = accountId;
    mockShownAccountId = undefined;
    renderCarouselWithGlobal();
  });
  root = document.createElement('div');
  document.body.append(root);
});

afterEach(async () => {
  TeactDOM.render(undefined, root);
  await jest.advanceTimersByTimeAsync(50);
  root.remove();
  jest.restoreAllMocks();
  jest.useRealTimers();
});

function renderCarouselWithGlobal() {
  const props = {
    accountId: mockAccountId,
    selectedId: mockShownAccountId ?? mockAccountId,
    accounts: ACCOUNT_IDS.map((id) => [id, { title: id }] as [string, Account]),
    isMotionDisabled,
    onYieldClick: mockHandleYieldClick,
  };

  TeactDOM.render(<CardCarousel {...props} />, root);
}

async function renderCarousel() {
  renderCarouselWithGlobal();
  await jest.advanceTimersByTimeAsync(50);
  viewport = root.querySelector('[dir="ltr"]')!;
}

function mockGetCarouselCardWidth() {
  return document.querySelector<HTMLElement>('[dir="ltr"]')!.style.getPropertyValue('--carousel-card-width');
}

function dispatchTouch(type: string, touches: unknown[], target: EventTarget = viewport) {
  const event = new Event(type, { bubbles: true });

  Object.assign(event, { touches });
  target.dispatchEvent(event);
}

function dispatchMouse(type: string, target: EventTarget, pageX: number) {
  const event = new MouseEvent(type, { bubbles: true, button: 0, buttons: 1 });

  Object.defineProperty(event, 'pageX', { value: pageX });
  target.dispatchEvent(event);
}

function scrollViewport(left: number) {
  viewport.scrollLeft = left;
  viewport.dispatchEvent(new Event('scroll'));
}

async function swipeTo(left: number) {
  dispatchTouch('touchstart', [{}]);
  scrollViewport(left);
  dispatchTouch('touchend', [], window);
  viewport.dispatchEvent(new Event('scrollend'));
  await jest.advanceTimersByTimeAsync(50);
}

function getRenderedAccountIds() {
  const accountIds = mockRenderCard.mock.calls.map(([{ accountId }]: [{ accountId: string }]) => accountId);

  return Array.from(new Set(accountIds)).sort((first, second) => (
    ACCOUNT_IDS.indexOf(first) - ACCOUNT_IDS.indexOf(second)
  ));
}

function declineSwitches() {
  mockSwitchToCardAccount.mockImplementation(() => {
    mockShownAccountId = undefined;
    renderCarouselWithGlobal();
  });
}

it('asks for the account of the card after the gesture settles', async () => {
  await renderCarousel();
  await swipeTo(CARD_STEP_PX);

  expect(mockSwitchToCardAccount).toHaveBeenCalledTimes(1);
  expect(mockSwitchToCardAccount).toHaveBeenCalledWith({ accountId: 'second' });
});

it('shows the nearest card without asking for its account while the finger is on the card', async () => {
  await renderCarousel();
  dispatchTouch('touchstart', [{}]);
  scrollViewport(CARD_STEP_PX);
  await jest.advanceTimersByTimeAsync(300);

  expect(mockShowCardAccount).toHaveBeenLastCalledWith({ accountId: 'second' });
  expect(mockSwitchToCardAccount).not.toHaveBeenCalled();
});

it('mounts only the settled card and its neighbours', async () => {
  await renderCarousel();

  expect(getRenderedAccountIds()).toEqual(['first', 'second']);

  mockRenderCard.mockClear();
  await swipeTo(CARD_STEP_PX);

  expect(getRenderedAccountIds()).toEqual(['first', 'second', 'third']);
});

it('drags the card with the mouse and stops at the neighbouring account', async () => {
  isMotionDisabled = true;
  await renderCarousel();
  dispatchMouse('mousedown', viewport, 1000);
  dispatchMouse('mousemove', window, 0);
  await jest.advanceTimersByTimeAsync(50);

  expect(viewport.scrollLeft).toBe(CARD_STEP_PX);

  viewport.dispatchEvent(new Event('scroll'));
  dispatchMouse('mouseup', window, 0);
  await jest.advanceTimersByTimeAsync(50);
  window.dispatchEvent(new Event('click'));

  expect(mockSwitchToCardAccount).toHaveBeenCalledWith({ accountId: 'second' });
});

it('gives the cards their width before they fit the balance font', async () => {
  mockCardLayoutEffect.mockClear();
  await renderCarousel();

  expect(mockCardLayoutEffect).toHaveBeenCalled();
  expect(mockCardLayoutEffect.mock.calls[0][0]).toBe('300px');
});

it('mounts a far account before moving there and keeps the shown card until then', async () => {
  isMotionDisabled = true;
  await renderCarousel();
  mockRenderCard.mockClear();
  mockAccountId = 'fifth';

  let scrollLeftOnMount: number | undefined;
  let isOldCardMountedWithNew = false;

  mockRenderCard.mockImplementation(({ accountId }: { accountId: string }) => {
    if (accountId !== 'fifth' || scrollLeftOnMount !== undefined) return;

    scrollLeftOnMount = viewport.scrollLeft;
    // Cards render in list order, so the card before `fourth` belongs to the same render as `fifth`
    isOldCardMountedWithNew = mockRenderCard.mock.calls.at(-3)?.[0].accountId === 'first';
  });

  await renderCarousel();
  await jest.advanceTimersByTimeAsync(100);
  mockRenderCard.mockReset();

  expect(scrollLeftOnMount).toBe(0);
  expect(isOldCardMountedWithNew).toBe(true);
  expect(viewport.scrollLeft).toBe(4 * CARD_STEP_PX);
});

it('pauses only the current card during a gesture', async () => {
  await renderCarousel();
  mockRenderCard.mockClear();
  dispatchTouch('touchstart', [{}]);
  scrollViewport(100);
  await jest.advanceTimersByTimeAsync(50);

  const pausedAccountIds = mockRenderCard.mock.calls
    .filter(([{ isPaused }]: [{ isPaused: boolean }]) => isPaused)
    .map(([{ accountId }]: [{ accountId: string }]) => accountId);

  expect(new Set(pausedAccountIds)).toEqual(new Set(['first']));
});

it('keeps the previous account card paused until the selected account activates', async () => {
  mockSwitchToCardAccount.mockReturnValue(new Promise(() => undefined));
  await renderCarousel();
  await swipeTo(CARD_STEP_PX);

  const previousCard = mockRenderCard.mock.calls
    .filter(([{ accountId }]: [{ accountId: string }]) => accountId === 'first').at(-1)![0];

  expect(mockAccountId).toBe('first');
  expect(previousCard).toMatchObject({ isActive: true, isPaused: true });

  mockAccountId = 'second';
  mockShownAccountId = undefined;
  await renderCarousel();

  const selectedCard = mockRenderCard.mock.calls
    .filter(([{ accountId }]: [{ accountId: string }]) => accountId === 'second').at(-1)![0];

  expect(selectedCard).toMatchObject({ isActive: true, isPaused: false });
});

it('keeps the settled card mounted while the destination artwork decodes', async () => {
  let finishDecoding!: NoneToVoidFunction;
  const decoding = new Promise<void>((resolve) => {
    finishDecoding = resolve;
  });

  mockRenderCard.mockImplementation(({ accountId }: { accountId: string }) => (
    <div data-rendered-account={accountId}>{accountId === 'fifth' && <img alt="" />}</div>
  ));
  mockCardLayoutEffect.mockImplementation(() => {
    const artwork = root.querySelector('img');
    if (artwork) artwork.decode = () => decoding;
  });
  await renderCarousel();
  mockAccountId = 'fifth';
  await renderCarousel();
  await jest.advanceTimersByTimeAsync(100);

  expect(viewport.scrollLeft).toBe(0);
  expect(root.querySelector('[data-rendered-account="first"]')).not.toBeNull();
  expect(root.querySelector('[data-rendered-account="fifth"]')).not.toBeNull();

  finishDecoding();
  await jest.advanceTimersByTimeAsync(50);

  expect(viewport.scrollLeft).toBe(4 * CARD_STEP_PX);
  expect(root.querySelector('[data-rendered-account="first"]')).toBeNull();
});

it('returns to the current account when the switch is declined', async () => {
  isMotionDisabled = true;
  declineSwitches();
  await renderCarousel();
  await swipeTo(CARD_STEP_PX);
  await jest.advanceTimersByTimeAsync(100);

  expect(mockAccountId).toBe('first');
  expect(viewport.scrollLeft).toBe(0);
});

it('follows an account that another flow has activated during a gesture', async () => {
  isMotionDisabled = true;
  declineSwitches();
  await renderCarousel();
  dispatchTouch('touchstart', [{}]);
  scrollViewport(CARD_STEP_PX);
  mockAccountId = 'third';
  await renderCarousel();
  dispatchTouch('touchend', [], window);
  viewport.dispatchEvent(new Event('scrollend'));
  await jest.advanceTimersByTimeAsync(100);

  expect(mockAccountId).toBe('third');
  expect(viewport.scrollLeft).toBe(2 * CARD_STEP_PX);
});

it('settles a gesture that the previous carousel did not finish', async () => {
  isMotionDisabled = true;
  mockShownAccountId = 'second';
  await renderCarousel();

  expect(viewport.scrollLeft).toBe(CARD_STEP_PX);
  expect(mockSwitchToCardAccount).toHaveBeenCalledWith({ accountId: 'second' });
});

it('preloads the artwork of every wallet, nearest first', async () => {
  mockAccountId = 'third';
  await renderCarousel();

  expect(preloadCardArtworks).toHaveBeenLastCalledWith([
    { address: 'third' }, { address: 'second' }, { address: 'fourth' }, { address: 'first' }, { address: 'fifth' },
  ]);
});

it('moves the mounted window to an account changed outside the carousel under a resting finger', async () => {
  await renderCarousel();
  dispatchTouch('touchstart', [{}]);
  mockRenderCard.mockClear();
  mockAccountId = 'fifth';
  await renderCarousel();

  expect(getRenderedAccountIds()).toEqual(expect.arrayContaining(['fourth', 'fifth']));
  expect(getRenderedAccountIds()).not.toContain('third');
});

it('aligns back after an external account switch under a stationary finger settles', async () => {
  await renderCarousel();
  dispatchTouch('touchstart', [{}]);
  mockAccountId = 'fifth';
  await renderCarousel();
  viewport.dispatchEvent(new Event('scroll'));
  dispatchTouch('touchend', [], window);
  await jest.advanceTimersByTimeAsync(100);
  mockAccountId = 'first';
  mockShownAccountId = undefined;
  await renderCarousel();
  await jest.advanceTimersByTimeAsync(100);

  expect(viewport.scrollLeft).toBe(0);
});
