import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';
import type { Account } from '../../global/types';
import type { TabWithProperties } from '../ui/TabList';

import { DEFAULT_CHAIN } from '../../config';
import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountState,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainTitle, getSupportedChains } from '../../util/chain';
import { swapKeysAndValues } from '../../util/iteratees';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TabList from '../ui/TabList';
import Transition from '../ui/Transition';
import Actions from './content/Actions';
import Address from './content/Address';

import styles from './ReceiveModal.module.scss';

interface StateProps {
  accountChains?: Account['byChain'];
  isLedger?: boolean;
  chain: ApiChain;
}

type OwnProps = {
  isOpen?: boolean;
  isStatic?: boolean;
  onClose?: NoneToVoidFunction;
};

const tabIdByChain = Object.fromEntries(
  getSupportedChains().map((chain, index) => [chain, index]),
) as Record<ReturnType<typeof getSupportedChains>[number], number>;

const chainByTabId = swapKeysAndValues(tabIdByChain);

function Content({
  isOpen, accountChains, chain, isStatic, isLedger, onClose,
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
        isStatic={isStatic}
        isLedger={isLedger}
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
      {isStatic && <Actions chain={chain} isStatic isLedger={isLedger} />}

      {tabs.length > 1 && (
        <TabList
          tabs={tabs}
          activeTab={activeTab}
          className={buildClassName(styles.tabs, !isStatic && styles.tabsInModal)}
          overlayClassName={buildClassName(styles.tabsOverlay, chain && styles[chain])}
          onSwitchTab={handleSwitchTab}
        />
      )}
      <Transition
        key={`content_${lang.code}`}
        activeKey={activeTab}
        name={isPortrait ? 'slide' : 'slideFade'}
        className={styles.contentWrapper}
        slideClassName={buildClassName(styles.content, isStatic && styles.contentStatic, 'custom-scroll')}
        shouldRestoreHeight={isStatic}
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
      chain: receiveModalChain ?? DEFAULT_CHAIN,
    };
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)))(Content),
);

function getChainTabs(accountChains: Partial<Record<ApiChain, unknown>>) {
  const result: TabWithProperties[] = [];

  for (const chain of getSupportedChains()) {
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
