import React, { memo, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';
import type { ApiTonPlugin, ApiWalletPermission } from '../../api/types/misc';
import type { Account } from '../../global/types';
import type { TabWithProperties } from '../ui/TabList';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../../config';
import {
  selectCurrentAccount,
  selectCurrentAccountId,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainConfig, getChainTitle, getOrderedAccountChains } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { shortenAddress } from '../../util/shortenAddress';
import { callApi } from '../../api';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useFlag from '../../hooks/useFlag';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import TokenIcon from '../common/TokenIcon';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Spinner from '../ui/Spinner';
import TabList from '../ui/TabList';
import Transition from '../ui/Transition';
import RevokeApprovalModal from './RevokeApprovalModal';
import SettingsHeader from './SettingsHeader';

import receiveStyles from '../receive/ReceiveModal.module.scss';
import styles from './Settings.module.scss';
import permStyles from './SettingsPermissions.module.scss';

const EXCLUDED_CHAINS = new Set<ApiChain>(['solana', 'tron']);

interface OwnProps {
  isActive: boolean;
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  accountId?: string;
  byChain?: Account['byChain'];
}

function SettingsPermissions({
  isActive,
  accountId,
  byChain,
  onBackClick,
}: OwnProps & StateProps) {
  const lang = useLang();

  const permissionChains = useMemo(() => {
    if (!byChain) return [];
    return getOrderedAccountChains(byChain).filter((chain) => !EXCLUDED_CHAINS.has(chain));
  }, [byChain]);

  const tabs = useMemo<TabWithProperties[]>(() => permissionChains.map((chain, index) => ({
    id: index,
    title: getChainTitle(chain),
    className: buildClassName(receiveStyles.tab, receiveStyles[chain]),
  })), [permissionChains]);

  const [activeTabIndex, setActiveTabIndex] = useState(0);
  const activeChain = permissionChains[activeTabIndex] ?? 'ton';

  const [permissions, setPermissions] = useState<ApiWalletPermission[] | undefined>(undefined);
  const [plugins, setPlugins] = useState<ApiTonPlugin[] | undefined>(undefined);
  const [isLoading, setIsLoading] = useState(false);
  const [selectedPermission, setSelectedPermission] = useState<ApiWalletPermission | undefined>();
  const [isRevokeModalOpen, openRevokeModal, closeRevokeModal] = useFlag();

  useHistoryBack({ isActive, onBack: onBackClick });

  const { handleScroll: handleContentScroll, isScrolled } = useScrolledState();

  const handleSwitchTab = useLastCallback((tabId: number) => {
    setActiveTabIndex(tabId);
  });

  const handlePermissionClick = useLastCallback((permission: ApiWalletPermission) => {
    setSelectedPermission(permission);
    openRevokeModal();
  });

  const handleRevokeSuccess = useLastCallback((permission: ApiWalletPermission) => {
    setPermissions((currentPermissions) => (
      currentPermissions?.filter((item) => {
        if (permission.kind === 'delegation') {
          return !(item.kind === 'delegation' && item.delegateAddress === permission.delegateAddress);
        }

        return !(
          item.kind === 'approval'
          && item.tokenSlug === permission.tokenSlug
          && item.spenderAddress === permission.spenderAddress
        );
      })
    ));
    setSelectedPermission(undefined);
  });

  const handleRevokeModalClose = useLastCallback(() => {
    closeRevokeModal();
    setSelectedPermission(undefined);
  });

  useEffect(() => {
    if (!accountId || !activeChain) return;

    const chainStandard = getChainConfig(activeChain).chainStandard;

    if (chainStandard === 'ethereum') {
      setPermissions(undefined);
      setIsLoading(true);
      void callApi('fetchWalletPermissions', accountId, activeChain).then((result) => {
        setPermissions(result ?? []);
        setIsLoading(false);
      });
      return;
    }

    if (activeChain === 'ton') {
      setPlugins(undefined);
      setIsLoading(true);
      void callApi('fetchWalletPlugins', accountId).then((result) => {
        setPlugins(result ?? []);
        setIsLoading(false);
      });
      return;
    }

    setIsLoading(false);
  }, [accountId, activeChain]);

  function renderLoadingState() {
    return (
      <div className={styles.emptyList}>
        <Spinner />
      </div>
    );
  }

  function renderEmptyState(isPlaying: boolean) {
    return (
      <div className={styles.emptyList}>
        <AnimatedIconWithPreview
          play={isPlaying}
          tgsUrl={ANIMATED_STICKERS_PATHS.noData}
          previewUrl={ANIMATED_STICKERS_PATHS.noDataPreview}
          size={ANIMATED_STICKER_BIG_SIZE_PX}
          noLoop={false}
          nonInteractive
        />
        <p className={styles.emptyListTitle}>{lang('No Permissions')}</p>
      </div>
    );
  }

  function renderDelegationRow(delegation: Extract<ApiWalletPermission, { kind: 'delegation' }>) {
    const delegateLabel = delegation.delegateName ?? shortenAddress(delegation.delegateAddress);

    return (
      <div
        key={`delegation:${delegation.delegateAddress}`}
        className={styles.item}
        onClick={() => handlePermissionClick(delegation)}
      >
        {delegation.delegateIcon && (
          <img src={delegation.delegateIcon} alt="" className={permStyles.delegateIcon} />
        )}
        <div className={permStyles.itemContent}>
          <span className={styles.itemTitle}>{delegateLabel}</span>
          <span className={styles.itemSubtitle}>{lang('Wallet Delegation')}</span>
        </div>
      </div>
    );
  }

  function renderPermissionRow(permission: ApiWalletPermission) {
    if (permission.kind === 'delegation') {
      return renderDelegationRow(permission);
    }

    return renderApprovalRow(permission);
  }

  function renderApprovalRow(approval: Extract<ApiWalletPermission, { kind: 'approval' }>) {
    const isUnlimited = approval.isUnlimited;
    const amountStr = isUnlimited
      ? lang('Unlimited')
      : formatCurrency(toDecimal(BigInt(approval.allowance), approval.tokenDecimals), approval.tokenSymbol);

    const spenderLabel = approval.spenderName ?? shortenAddress(approval.spenderAddress);

    const fakeToken = {
      slug: approval.tokenSlug,
      name: approval.tokenName,
      symbol: approval.tokenSymbol,
      image: approval.tokenImage,
      decimals: approval.tokenDecimals,
      chain: approval.chain,
    };

    return (
      <div
        key={`${approval.tokenSlug}:${approval.spenderAddress}`}
        className={styles.item}
        onClick={() => handlePermissionClick(approval)}
      >
        <TokenIcon token={fakeToken} size="small">
          {approval.spenderIcon && (
            <img src={approval.spenderIcon} alt="" className={permStyles.spenderBadge} />
          )}
        </TokenIcon>
        <div className={permStyles.itemContent}>
          <span className={styles.itemTitle}>{approval.tokenName}</span>
          <span className={styles.itemSubtitle}>
            {lang('Approved to %name%', { name: spenderLabel })}
          </span>
        </div>
        <span className={styles.itemSubtitle}>{amountStr}</span>
      </div>
    );
  }

  function renderPluginRow(plugin: ApiTonPlugin) {
    const name = plugin.name ?? lang('Unknown Plugin');

    return (
      <div key={plugin.address} className={styles.item}>
        <div className={permStyles.itemContent}>
          <span className={styles.itemTitle}>{name}</span>
          <span className={styles.itemSubtitle}>{shortenAddress(plugin.address)}</span>
        </div>
      </div>
    );
  }

  function renderChainContent(isContentActive: boolean) {
    const chainStandard = getChainConfig(activeChain).chainStandard;

    if (chainStandard === 'ethereum') {
      if (isLoading || permissions === undefined) {
        return renderLoadingState();
      }
      if (!permissions.length) {
        return renderEmptyState(isContentActive);
      }
      return (
        <div className={styles.block}>
          {permissions.map(renderPermissionRow)}
        </div>
      );
    }

    if (activeChain === 'ton') {
      if (isLoading || plugins === undefined) {
        return renderLoadingState();
      }
      if (!plugins.length) {
        return renderEmptyState(isContentActive);
      }
      return (
        <div className={styles.block}>
          {plugins.map(renderPluginRow)}
        </div>
      );
    }

    return renderEmptyState(isContentActive);
  }

  return (
    <div className={styles.slide}>
      <SettingsHeader title={lang('Permissions')} isScrolled={isScrolled} onBackClick={onBackClick} />

      <div className={buildClassName(styles.content, 'custom-scroll')} onScroll={handleContentScroll}>
        {tabs.length > 1 && (
          <TabList
            tabs={tabs}
            activeTab={activeTabIndex}
            className={receiveStyles.tabs}
            overlayClassName={buildClassName(receiveStyles.tabsOverlay, receiveStyles[activeChain])}
            onSwitchTab={handleSwitchTab}
            isActive={isActive}
          />
        )}

        <Transition activeKey={activeTabIndex} name="fade">
          {renderChainContent}
        </Transition>
      </div>

      <RevokeApprovalModal
        isOpen={isRevokeModalOpen}
        accountId={accountId}
        permission={selectedPermission}
        onClose={handleRevokeModalClose}
        onSuccess={handleRevokeSuccess}
      />
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>((global): StateProps => {
    const account = selectCurrentAccount(global);
    return {
      accountId: selectCurrentAccountId(global),
      byChain: account?.byChain,
    };
  })(SettingsPermissions),
);
