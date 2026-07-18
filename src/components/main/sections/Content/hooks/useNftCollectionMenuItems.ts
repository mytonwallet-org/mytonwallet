import { useMemo } from '../../../../../lib/teact/teact';

import type { ApiNft } from '../../../../../api/types';
import type { DropdownItem } from '../../../../ui/Dropdown';

import {
  IS_FEATURE_LIMITED,
  IS_MY_WALLET_BRAND,
  MW_CARDS_COLLECTION,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
} from '../../../../../config';
import { buildNftCollectionIndex, getCollectionKey } from '../../../../../global/helpers/nfts';

import useLang from '../../../../../hooks/useLang';

export const HIDDEN_NFTS_VALUE = 'hidden_nfts';

const TELEGRAM_GIFTS_KEY = getCollectionKey('ton', TELEGRAM_GIFTS_SUPER_COLLECTION);
const TELEGRAM_GIFTS_VALUE = `${TELEGRAM_GIFTS_SUPER_COLLECTION}@ton`;

const MW_CARDS_KEY = getCollectionKey('ton', MW_CARDS_COLLECTION);
const MW_CARDS_VALUE = `${MW_CARDS_COLLECTION}@ton`;

export default function useNftCollectionMenuItems({
  nfts,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
}: {
  nfts?: Record<string, ApiNft>;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
}) {
  const lang = useLang();

  return useMemo(() => {
    const { byKey, totalVisibleCount } = buildNftCollectionIndex(
      nfts, blacklistedNftAddresses, whitelistedNftAddresses,
    );

    const hasTelegramGifts = byKey.has(TELEGRAM_GIFTS_KEY);
    const hasMwCards = IS_MY_WALLET_BRAND && byKey.has(MW_CARDS_KEY);
    const telegramGiftsName = lang('Telegram Gifts');
    const unnamedLabel = lang('Unnamed Collection');

    const nameByKey = new Map<string, string>();
    const items: DropdownItem[] = [];

    for (const [key, { chain, address, name }] of byKey) {
      if (key === TELEGRAM_GIFTS_KEY) {
        nameByKey.set(key, telegramGiftsName);
        continue;
      }
      const resolvedName = name || unnamedLabel;
      nameByKey.set(key, resolvedName);
      if (key === MW_CARDS_KEY && hasMwCards) continue;
      items.push({ value: `${address}@${chain}`, name: resolvedName, noTranslate: true });
    }

    items.sort((a, b) => a.name.localeCompare(b.name));

    if (hasMwCards) {
      items.unshift({
        value: MW_CARDS_VALUE,
        name: nameByKey.get(MW_CARDS_KEY) ?? unnamedLabel,
        fontIcon: 'card-alt',
        withDelimiterAfter: true,
        noTranslate: true,
      });
    }

    if (hasTelegramGifts) {
      items.unshift({
        value: TELEGRAM_GIFTS_VALUE,
        name: telegramGiftsName,
        fontIcon: 'gift',
        withDelimiterAfter: !hasMwCards,
        noTranslate: true,
      });
    }

    const blacklistedSet = new Set(blacklistedNftAddresses);
    const shouldRenderHiddenNftsSection = !IS_FEATURE_LIMITED && Object.values(nfts ?? {}).some(
      (nft) => blacklistedSet.has(nft.address) || nft.isHidden,
    );

    return { items, nameByKey, shouldRenderHiddenNftsSection, byKey, totalVisibleCount };
  }, [lang, nfts, blacklistedNftAddresses, whitelistedNftAddresses]);
}
