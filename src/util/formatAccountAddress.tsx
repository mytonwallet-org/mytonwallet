import type { TeactNode } from '../lib/teact/teact';
import React from '../lib/teact/teact';

import type { ApiChain } from '../api/types';
import type { Account } from '../global/types';

import { shortenAddress } from './shortenAddress';

type FormatVariant = 'card' | 'list';

type FormatConfig = {
  single: [left: number, right: number];
  domain: [left: number, right: number];
  address: [left: number, right: number];
};

const FORMAT_CONFIG: Record<FormatVariant, FormatConfig> = {
  card: {
    single: [3, 4],
    domain: [3, 2],
    address: [0, 3],
  },
  list: {
    single: [6, 6],
    domain: [4, 4],
    address: [0, 4],
  },
};

export function formatAccountAddresses(
  byChain: Account['byChain'],
  variant: FormatVariant = 'card',
): TeactNode | undefined {
  const chains = Object.keys(byChain) as ApiChain[];
  if (chains.length === 0) return undefined;

  // Single-chain account
  if (chains.length === 1) {
    const chain = chains[0];
    const account = byChain[chain];

    if (!account) return undefined;

    return (
      <>
        {renderIcon(chain)}
        {getShortText(account.domain ?? account.address, variant, 'single')}
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
      elements.push(', ');
    }
    elements.push(renderIcon(chain), displayText);
  });

  return <>{elements}</>;
}

function getShortText(text: string, variant: FormatVariant, type: keyof FormatConfig) {
  const [left, right] = FORMAT_CONFIG[variant][type];

  return shortenAddress(text, left, right);
}

function renderIcon(chain: ApiChain) {
  return <i key={`icon-${chain}`} className={`icon-chain-${chain}`} aria-hidden />;
}
