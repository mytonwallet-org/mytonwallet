import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';
import type { ChainDisplay } from '../../global/selectors';
import type { Account } from '../../global/types';
import type { TabWithProperties } from '../ui/TabList';

import { DEFAULT_CHAIN } from '../../config';
import {
  selectCurrentAccount,
  selectCurrentAccountChainDisplay,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainTitle, getDisplayOrderedChains } from '../../util/chain';
import { swapKeysAndValues } from '../../util/iteratees';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TabList from '../ui/TabList';
import Transition from '../ui/Transition';
import Address from './content/Address';

import styles from './ReceiveModal.module.scss';

const ORDERED_SUPPORTED_CHAINS = getDisplayOrderedChains();
const EMPTY_CHAINS: ApiChain[] = [];

interface StateProps {
  accountChains?: Account['byChain'];
  chainDisplay?: ChainDisplay;
  isLedger?: boolean;
  isViewMode: boolean;
  receiveModalChain?: ApiChain;
}

type OwnProps = {
  isOpen?: boolean;
  onClose?: NoneToVoidFunction;
};

const tabIdByChain = Object.fromEntries(
  ORDERED_SUPPORTED_CHAINS.map((chain, index) => [chain, index]),
) as Record<ApiChain, number>;

const chainByTabId = swapKeysAndValues(tabIdByChain);

function Content({
  isOpen, accountChains, chainDisplay, receiveModalChain, isLedger, isViewMode, onClose,
}: StateProps & OwnProps) {
  const { setReceiveActiveTab } = getActions();

  // `lang.code` is used to force redrawing of the `Transition` content,
  // since the height of the content differs from translation to translation.
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();

  // Every chain of the account is available here, hidden ones included, in the Blockchains screen order
  const chains = chainDisplay?.orderedChains ?? EMPTY_CHAINS;
  const tabs = useMemo(() => getChainTabs(chains), [chains]);
  const defaultChain = chains.includes(DEFAULT_CHAIN) || !chains.length
    ? DEFAULT_CHAIN
    : chains[0];
  const chain = receiveModalChain && chains.includes(receiveModalChain) ? receiveModalChain : defaultChain;
  const activeTab = tabIdByChain[chain];
  // `TabList` addresses its tabs by position, while `activeTab` is the chain position in the full chain order
  const activeTabIndex = tabs.findIndex((tab) => tab.id === activeTab);

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
          isActive={isOpen}
          tabs={tabs}
          activeTab={activeTabIndex}
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
      chainDisplay: selectCurrentAccountChainDisplay(global),
      isLedger: account?.type === 'hardware',
      isViewMode: selectIsCurrentAccountViewMode(global),
      receiveModalChain,
    };
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)))(Content),
);

function getChainTabs(chains: ApiChain[]): TabWithProperties[] {
  return chains.map((chain) => ({
    id: tabIdByChain[chain],
    title: getChainTitle(chain),
    className: buildClassName(styles.tab, styles[chain]),
  }));
}
