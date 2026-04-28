import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';
import type { Account } from '../../global/types';
import type { TabWithProperties } from '../ui/TabList';

import { DEFAULT_CHAIN, PRIORITY_TOKENS } from '../../config';
import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainTitle, getSupportedChains } from '../../util/chain';
import { swapKeysAndValues } from '../../util/iteratees';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TabList from '../ui/TabList';
import Transition from '../ui/Transition';
import Address from './content/Address';

import styles from './ReceiveModal.module.scss';

const CHAIN_ORDER = PRIORITY_TOKENS.reduce((acc, token) => {
  if (!acc.has(token.chain)) {
    acc.set(token.chain, acc.size);
  }

  return acc;
}, new Map<ApiChain, number>());

const ORDERED_SUPPORTED_CHAINS = getSupportedChains()
  .map((chain, index) => ({ chain, index }))
  .sort((a, b) => {
    const orderDiff = (CHAIN_ORDER.get(a.chain) ?? Infinity) - (CHAIN_ORDER.get(b.chain) ?? Infinity);

    return orderDiff || a.index - b.index;
  })
  .map(({ chain }) => chain);

interface StateProps {
  accountChains?: Account['byChain'];
  isLedger?: boolean;
  isViewMode: boolean;
  chain: ApiChain;
}

type OwnProps = {
  isOpen?: boolean;
  onClose?: NoneToVoidFunction;
};

const tabIdByChain = Object.fromEntries(
  ORDERED_SUPPORTED_CHAINS.map((chain, index) => [chain, index]),
) as Record<ReturnType<typeof getSupportedChains>[number], number>;

const chainByTabId = swapKeysAndValues(tabIdByChain);

function Content({
  isOpen, accountChains, chain, isLedger, isViewMode, onClose,
}: StateProps & OwnProps) {
  const { setReceiveActiveTab } = getActions();

  // `lang.code` is used to force redrawing of the `Transition` content,
  // since the height of the content differs from translation to translation.
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();

  const tabs = useMemo(() => getChainTabs(accountChains ?? {}), [accountChains]);
  const activeTab = tabIdByChain[chain];

  const handleSwitchTab = useLastCallback((tabId: number) => {
    const newChain = chainByTabId[tabId];
    if (newChain) {
      setReceiveActiveTab({ chain: newChain });
    }
  });

  function renderAddress(isActive: boolean, isFrom: boolean, currentKey: number) {
    const chain = chainByTabId[currentKey];

    return (
      <Address
        chain={chain}
        isActive={isOpen && isActive}
        isLedger={isLedger}
        isViewMode={isViewMode}
        address={accountChains?.[chain]?.address ?? ''}
        onClose={onClose}
      />
    );
  }

  if (!tabs.length) {
    return undefined;
  }

  return (
    <>
      {tabs.length > 1 && (
        <TabList
          tabs={tabs}
          activeTab={activeTab}
          className={styles.tabs}
          overlayClassName={buildClassName(styles.tabsOverlay, chain && styles[chain])}
          onSwitchTab={handleSwitchTab}
        />
      )}
      <Transition
        key={`content_${lang.code}`}
        activeKey={activeTab}
        name={isPortrait ? 'slide' : 'semiFade'}
        className={styles.contentWrapper}
        slideClassName={buildClassName(styles.content, 'custom-scroll')}
      >
        {renderAddress}
      </Transition>
    </>
  );
}

export default memo(
  withGlobal<OwnProps>((global): StateProps => {
    const account = selectCurrentAccount(global);
    const { receiveModalChain } = selectCurrentAccountState(global) || {};

    return {
      accountChains: account?.byChain,
      isLedger: account?.type === 'hardware',
      isViewMode: selectIsCurrentAccountViewMode(global),
      chain: receiveModalChain ?? DEFAULT_CHAIN,
    };
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)))(Content),
);

function getChainTabs(accountChains: Partial<Record<ApiChain, unknown>>) {
  const result: TabWithProperties[] = [];

  for (const chain of ORDERED_SUPPORTED_CHAINS) {
    if (!(chain in accountChains)) {
      continue;
    }

    result.push({
      id: tabIdByChain[chain],
      title: getChainTitle(chain),
      className: buildClassName(styles.tab, styles[chain]),
    });
  }

  return result;
}
