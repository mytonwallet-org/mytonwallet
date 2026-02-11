import type { TeactNode } from '../lib/teact/teact';
import React from '../lib/teact/teact';

import type { ApiChain } from '../api/types';
import type { Account } from '../global/types';

import { getOrderedAccountChains } from './chain';
import { shortenAddress } from './shortenAddress';
import { shortenDomain } from './shortenDomain';

type FormatVariant = 'card' | 'cardNarrow' | 'list';

type FormatConfig = {
  single: [left: number, right: number];
  domain: number;
  address: [left: number, right: number];
};

const FORMAT_CONFIG: Record<FormatVariant, FormatConfig> = {
  card: {
    single: [3, 4],
    domain: 8,
    address: [0, 3],
  },
  cardNarrow: {
    single: [3, 3],
    domain: 6,
    address: [0, 2],
  },
  list: {
    single: [6, 6],
    domain: 12,
    address: [0, 4],
  },
};

export function formatAccountAddresses(
  byChain: Account['byChain'],
  variant: FormatVariant = 'card',
): TeactNode | undefined {
  const chains = getOrderedAccountChains(byChain);
  if (chains.length === 0) return undefined;

  // Single-chain account
  if (chains.length === 1) {
    const chain = chains[0];
    const wallet = byChain[chain];

    if (!wallet) return undefined;

    const text = wallet.domain ?? wallet.address;
    const type = wallet.domain ? 'domain' : 'single';

    return (
      <>
        {renderIcon(chain)}
        {getShortText(text, variant, type)}
      </>
    );
  }

  // Multi-chain account
  const elements: TeactNode[] = [];

  chains.forEach((chain, index) => {
    const account = byChain[chain];
    if (!account) return;

    const isDomain = Boolean(account.domain);
    const displayText = getShortText(account.domain ?? account.address, variant, isDomain ? 'domain' : 'address');

    if (index > 0) {
      elements.push(variant === 'list' ? ', ' : ' ');
    }
    elements.push(renderIcon(chain), displayText);
  });

  return <>{elements}</>;
}

function getShortText(text: string, variant: FormatVariant, type: keyof FormatConfig) {
  const config = FORMAT_CONFIG[variant];

  if (type === 'domain') {
    return shortenDomain(text, config.domain);
  }

  const [left, right] = config[type] as [number, number];
  return shortenAddress(text, left, right);
}

function renderIcon(chain: ApiChain) {
  return <i key={`icon-${chain}`} className={`icon-chain-${chain}`} aria-hidden />;
}
