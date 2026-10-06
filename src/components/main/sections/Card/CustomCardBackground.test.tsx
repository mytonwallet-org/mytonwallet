import React from '../../../../lib/teact/teact';
import TeactDOM from '../../../../lib/teact/teact-dom';

import type { ApiNft } from '../../../../api/types';

import { pause } from '../../../../util/schedulers';

import CustomCardBackground from './CustomCardBackground';

jest.mock('../../../../hooks/useCachedImage', () => ({
  useCachedImage: () => ({ imageUrl: 'blob:card-artwork' }),
}));
jest.mock('../../../ui/CardBackgroundMotion', () => ({
  __esModule: true,
  default: () => undefined,
}));

const CARD_NFT: ApiNft = {
  chain: 'ton',
  interface: 'default',
  index: 0,
  name: 'Gold Card',
  address: 'EQCardNftAddress',
  isOnSale: false,
  metadata: { mtwCardId: 1, mtwCardType: 'gold' },
};

// Teact re-renders on rAF, `useShowTransition` opens the card in the next measure phase
const flushUpdates = () => pause(50);

let root: HTMLDivElement;

beforeEach(() => {
  root = document.createElement('div');
  document.body.appendChild(root);
});

afterEach(() => {
  TeactDOM.render(undefined, root);
  root.remove();
});

function renderCard(noShowAnimation: boolean) {
  TeactDOM.render(
    <CustomCardBackground nft={CARD_NFT} noShowAnimation={noShowAnimation} onTransitionEnd={() => {}} />,
    root,
  );
}

// Loads the artwork and returns the class list the card ends up with after each batch of DOM updates.
// The classes are toggled one by one, so the states inside a batch are never drawn and are skipped.
async function loadArtwork() {
  const card = root.firstElementChild as HTMLElement;
  const classLists: string[][] = [];
  const observer = new MutationObserver(() => {
    classLists.push(Array.from(card.classList));
  });
  observer.observe(card, { attributeFilter: ['class'] });

  card.querySelector('img')!.dispatchEvent(new Event('load'));
  await flushUpdates();
  observer.disconnect();

  return classLists;
}

function getHasFaded(classLists: string[][]) {
  return classLists.some((classList) => classList.includes('shown') && classList.includes('not-open'));
}

it('shows the initial card without a fade when its manager re-renders before the artwork loads', async () => {
  renderCard(true);
  await flushUpdates();
  // `CustomCardManager` passes `noShowAnimation` only on its first render
  renderCard(false);
  await flushUpdates();

  const classLists = await loadArtwork();

  expect(classLists.at(-1)).toContain('open');
  expect(getHasFaded(classLists)).toBe(false);
});

it('fades in a card that is not the initial one', async () => {
  renderCard(false);
  await flushUpdates();

  const classLists = await loadArtwork();

  expect(classLists.at(-1)).toContain('open');
  expect(getHasFaded(classLists)).toBe(true);
});
