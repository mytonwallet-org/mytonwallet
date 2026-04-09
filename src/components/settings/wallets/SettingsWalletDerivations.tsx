import React, { memo, useEffect, useMemo, useState } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type {
  ApiBaseCurrency,
  ApiChain,
  ApiNetwork,
  ApiWalletByChain,
  ApiWalletVariant,
} from '../../../api/types';
import type { UserToken } from '../../../global/types';

import { ANIMATED_STICKER_SMALL_SIZE_PX } from '../../../config';
import { selectAccount, selectCurrentAccountId, selectCurrentAccountTokens } from '../../../global/selectors';
import { parseAccountId } from '../../../util/account';
import buildClassName from '../../../util/buildClassName';
import { getChainConfig } from '../../../util/chain';
import { toBig, toDecimal } from '../../../util/decimals';
import { formatCurrency, getShortCurrencySymbol } from '../../../util/formatNumber';
import { pause } from '../../../util/schedulers';
import { shortenAddress } from '../../../util/shortenAddress';
import { callApi } from '../../../api';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import { useTransitionActiveKey } from '../../../hooks/useTransitionActiveKey';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Spinner from '../../ui/Spinner';
import Transition from '../../ui/Transition';
import WalletVariantListItem from './WalletVariantListItem';

import styles from '../Settings.module.scss';

interface OwnProps {
  isActive?: boolean;
  chain: ApiChain;
  password?: string;
  cachedDerivations?: ApiWalletVariant<ApiChain>[];
  onBack: NoneToVoidFunction;
  onWalletClick?: (chain: ApiChain, newWallet: Omit<ApiWalletByChain[ApiChain], 'index'>) => void;
  onDerivationsLoaded?: (chain: ApiChain, results: ApiWalletVariant<ApiChain>[]) => void;
}

interface StateProps {
  network: ApiNetwork;
  accountId: string;
  isTestnetSubwalletId?: boolean;
  tokens?: UserToken[];
  baseCurrency: ApiBaseCurrency;
  currentAddress?: string;
}

const SEARCH_PAUSE = 5_000;
const MAX_EMPTY_RESULTS_IN_ROW = 5;

function SettingsWalletDerivations({
  isActive,
  network,
  chain,
  accountId,
  isTestnetSubwalletId,
  tokens,
  baseCurrency,
  password,
  currentAddress,
  cachedDerivations,
  onBack: navigateBackToChains,
  onWalletClick,
  onDerivationsLoaded,
}: OwnProps & StateProps) {
  const { addSubWallet } = getActions();

  const lang = useLang();
  const [derivationsError, setDerivationsError] = useState<string>();
  const [derivations, setDerivations] = useState<ApiWalletVariant<ApiChain>[]>([]);
  const [isLoadingDerivations, setIsLoadingDerivations] = useState(true);

  useEffect(() => {
    if (!isActive || !password) return undefined;

    if (cachedDerivations && cachedDerivations.length > 0) {
      setDerivations(cachedDerivations);
      setIsLoadingDerivations(false);
      return undefined;
    }

    const currentChain = chain;
    const currentNetwork = network;
    const currentAccountId = accountId;
    const currentIsTestnetSubwalletId = isTestnetSubwalletId;
    let isCancelled = false;

    setDerivationsError(undefined);
    setDerivations([]);
    setIsLoadingDerivations(true);

    const runSearch = async () => {
      const mnemonicResult = await callApi('fetchMnemonic', currentAccountId, password);

      if (!mnemonicResult) {
        setDerivationsError('Unexpected error');
        return;
      }

      let page = 0;
      let emptyResultCounter = 0;
      const knownAddresses = new Set<string>();
      const allResults: ApiWalletVariant<ApiChain>[] = [];

      try {
        while (!isCancelled) {
          const derivationsResult = await callApi(
            'getWalletVariants',
            currentNetwork,
            currentChain,
            currentAccountId,
            page,
            currentIsTestnetSubwalletId,
            mnemonicResult,
          );

          if (!derivationsResult || 'error' in derivationsResult) {
            if (!isCancelled) {
              setDerivationsError(derivationsResult?.error ?? 'Unexpected error');
            }
            break;
          }

          if (isCancelled) break;

          const newItems = derivationsResult.filter((item) => !knownAddresses.has(item.wallet.address));
          const hasPositiveBalance = derivationsResult.some((item) => item.balance > 0n);

          if (newItems.length > 0) {
            newItems.forEach((item) => knownAddresses.add(item.wallet.address));
            allResults.push(...newItems);
            setDerivations((prev) => prev.concat(newItems));
          }

          emptyResultCounter = hasPositiveBalance ? 0 : emptyResultCounter + 1;
          page += 1;

          if (isCancelled || emptyResultCounter >= MAX_EMPTY_RESULTS_IN_ROW) break;

          await pause(SEARCH_PAUSE);
        }
      } finally {
        if (!isCancelled) {
          if (allResults.length > 0) {
            onDerivationsLoaded?.(currentChain, allResults);
          }
          setIsLoadingDerivations(false);
        }
      }
    };

    void runSearch();

    return () => {
      isCancelled = true;
    };
  }, [accountId, cachedDerivations, chain, isActive, isTestnetSubwalletId, network, onDerivationsLoaded, password]);

  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);

  const nativeToken = useMemo(() => tokens?.find(({ slug }) =>
    slug === getChainConfig(chain).nativeToken?.slug),
  [tokens, chain]);

  const wallets = useMemo(() => {
    return derivations
      .filter((v) => v.balance > 0n && (!currentAddress || v.wallet.address !== currentAddress))
      .map((derivation) => {
        const address = derivation.wallet.address ?? '';
        const title = derivation.metadata.type === 'path'
          ? `#${(derivation.wallet.derivation?.index || 0) + 1}`
          : derivation.metadata.version;

        const balanceInCurrency = formatCurrency(
          toBig(derivation.balance).mul(nativeToken?.price ?? 0).round(nativeToken?.decimals),
          shortBaseSymbol,
        );

        const nativeBalance = formatCurrency(toDecimal(derivation.balance), nativeToken?.symbol ?? '');
        const label = derivation.metadata.type === 'path' ? derivation.metadata.label : '';

        return {
          address,
          title,
          balanceInCurrency,
          nativeBalance,
          label,
          clickArg: {
            chain,
            newWallet: {
              address,
              publicKey: derivation.wallet.publicKey,
              version: chain === 'ton'
                ? (derivation.metadata.type === 'version' ? derivation.metadata.version : 'W5')
                : undefined,
              derivation: derivation.wallet.derivation,
            } as Omit<ApiWalletByChain[ApiChain], 'index'>,
            isReplace: true,
          },
        };
      });
  }, [
    chain, currentAddress, derivations, nativeToken?.decimals, nativeToken?.price,
    nativeToken?.symbol, shortBaseSymbol,
  ]);

  const hasWallets = wallets.length > 0;
  const activeKey = useTransitionActiveKey([hasWallets, isLoadingDerivations]);

  const cleanup = useLastCallback(() => {
    setIsLoadingDerivations(false);
    setDerivationsError(undefined);
    setDerivations([]);
  });

  const handleBackToChainsClick = useLastCallback(() => {
    navigateBackToChains();
    cleanup();
  });

  const handleSwitchWallet = useLastCallback((
    _e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>,
    arg: {
      chain: ApiChain;
      newWallet: Omit<ApiWalletByChain[ApiChain], 'index'>;
      isReplace: boolean;
    }) => {
    if (onWalletClick) {
      onWalletClick(arg.chain, arg.newWallet);
      return;
    }
    addSubWallet(arg);
    handleBackToChainsClick();
  });

  function renderScanningEmpty() {
    return (
      <div className={styles.emptyList}>
        <AnimatedIconWithPreview
          play={isActive}
          tgsUrl={ANIMATED_STICKERS_PATHS.wait}
          previewUrl={ANIMATED_STICKERS_PATHS.waitPreview}
          size={ANIMATED_STICKER_SMALL_SIZE_PX}
          nonInteractive
          noLoop={false}
        />
        <p className={styles.emptyListTitle}>
          {lang('Scanning for subwallets...')}
        </p>
        <p className={styles.emptyListText}>{lang('This process may take up to a minute. Please wait.')}</p>
        <p className={styles.emptyListText}>
          {lang('You can create a new subwallet if you need another address on the same recovery phrase.')}
        </p>
      </div>
    );
  }

  function renderNoResultsEmpty() {
    return (
      <div className={styles.emptyList}>
        <AnimatedIconWithPreview
          play={isActive}
          tgsUrl={ANIMATED_STICKERS_PATHS.noData}
          previewUrl={ANIMATED_STICKERS_PATHS.noDataPreview}
          size={ANIMATED_STICKER_SMALL_SIZE_PX}
          nonInteractive
          noLoop={false}
        />
        <p className={styles.emptyListTitle}>
          {lang('No existing subwallets found')}
        </p>
        <p className={styles.emptyListText}>
          {lang('You can create a new subwallet if you need another address on the same recovery phrase.')}
        </p>
      </div>
    );
  }

  function renderDerivationList() {
    if (derivationsError) {
      return (
        <div className={styles.emptyList}>
          <span className={styles.emptyListTitle}>{lang(derivationsError)}</span>
        </div>
      );
    }

    return (
      <>
        <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
          {wallets.map((w) => (
            <WalletVariantListItem
              key={w.address}
              title={w.title}
              subtitle={shortenAddress(w.address) ?? ''}
              tokens={w.nativeBalance}
              totalBalance={w.balanceInCurrency}
              label={w.label}
              onClick={handleSwitchWallet}
              clickArg={w.clickArg}
            />
          ))}
        </div>
        <div className={styles.blockDescription}>
          {lang('You have tokens on other subwallets. Each subwallet has its own address.')}
        </div>
        <div className={styles.blockDescription}>
          {lang('You can create a new subwallet if you need another address on the same recovery phrase.')}
        </div>
      </>
    );
  }

  return (
    <Transition activeKey={activeKey} name="fade" slideClassName={styles.transitionSlide}>
      {!hasWallets ? (
        isLoadingDerivations ? renderScanningEmpty() : renderNoResultsEmpty()
      ) : (
        <div>
          <div className={styles.blockTitleRow}>
            <p className={buildClassName(styles.blockTitle, styles.blockTitle_small)}>{lang('Subwallets')}</p>
            {isLoadingDerivations && (
              <span className={styles.scanningLabel}>
                <Spinner className={styles.scanningSpinner} />
                {lang('Scanning...')}
              </span>
            )}
          </div>

          {renderDerivationList()}
        </div>
      )}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global, ownProps): StateProps => {
  const currentAccountId = selectCurrentAccountId(global);
  const { network } = parseAccountId(currentAccountId!);
  const account = selectAccount(global, currentAccountId!);

  return {
    network,
    accountId: currentAccountId!,
    isTestnetSubwalletId: network === 'testnet',
    tokens: selectCurrentAccountTokens(global),
    baseCurrency: global.settings.baseCurrency,
    currentAddress: account?.byChain[ownProps.chain]?.address,
  };
})(SettingsWalletDerivations));
