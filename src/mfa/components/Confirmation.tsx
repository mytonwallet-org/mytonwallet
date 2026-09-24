import type { Address } from '@ton/core';
import { Cell } from '@ton/core';
import React, { memo, useEffect, useState } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type {
  ApiBaseCurrency,
  ApiCurrencyRates,
  ApiEmulationResult,
  ApiNft,
  ApiStakingState,
  ApiSwapAsset,
  ApiTokenWithPrice,
} from '../../api/types';
import type { Account, SavedAddress, Theme } from '../../global/types';
import type { ApiTransaction } from '../types';

import { TONCOIN } from '../../config';
import { ANIMATED_STICKER_MIDDLE_SIZE_PX } from '../config';
import {
  selectAccountStakingStatesByPool,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectNetworkAccounts,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getTelegramApp } from '../../util/telegram';
import { ANIMATED_STICKERS_PATHS } from '../../components/ui/helpers/animatedAssets';
import { ensureMfaTokenInfoReady } from '../runtime';
import { checkTransaction, resolveExtensionAddress, sendActions } from '../utils/extension';
import { confirmTransaction } from '../utils/transaction';

import useAppTheme from '../../hooks/useAppTheme';
import useLang from '../../hooks/useLang';

import { OpCode } from '../../api/chains/ton/contracts/MfaExtension';
import ActivityPreview from '../../components/common/ActivityPreview';
import DappSkeletonWithContent, { type DappSkeletonRow } from '../../components/dapps/DappSkeletonWithContent';
import AnimatedIconWithPreview from '../../components/ui/AnimatedIconWithPreview';
import UniversalButton from './UniversalButton';

import commonStyles from './_common.module.scss';
import styles from './Confirmation.module.scss';

interface OwnProps {
  transaction?: ApiTransaction;
  error?: string;
  requestId?: string;

  isLoading: boolean;
  isActive: boolean;

  onConfirm: () => void;
}

interface StateProps {
  tokensBySlug: Record<string, ApiTokenWithPrice>;
  swapTokensBySlug?: Record<string, ApiSwapAsset>;
  theme: Theme;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  nftsByAddress?: Record<string, ApiNft>;
  currentAccountId?: string;
  stakingStateByPool: Record<string, ApiStakingState>;
  savedAddresses?: SavedAddress[];
  accounts?: Record<string, Account>;
}

enum States {
  LOADING,
  CHECKING,
  READY,
  PROCESSING,
  UNINSTALLED,
  ERROR,
}

const actionSkeletonRows: DappSkeletonRow[] = [
  { isLarge: true, hasFee: true },
];

function Confirmation({
  transaction,
  error: transactionError,
  requestId,
  isLoading,
  isActive,
  tokensBySlug,
  swapTokensBySlug,
  theme,
  baseCurrency,
  currencyRates,
  nftsByAddress,
  currentAccountId,
  stakingStateByPool,
  savedAddresses,
  accounts,
  onConfirm,
}: OwnProps & StateProps) {
  const [currentState, setState] = useState<States>(States.LOADING);
  const [extensionAddress, setExtensionAddress] = useState<Address | undefined>(undefined);
  const [activeTelegramId, setActiveTelegramId] = useState<string | undefined>(undefined);
  const [emulation, setEmulation] = useState<Pick<ApiEmulationResult, 'activities' | 'realFee'> | undefined>(
    undefined,
  );
  const [areActionsLoading, setAreActionsLoading] = useState(false);
  const [error, setError] = useState<string | undefined>(undefined);
  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const title = transaction
    ? getPayloadOpCode(transaction.payload) === OpCode.REMOVE_EXTENSION
      ? lang('Confirm Unlinking')
      : lang('Is it all ok?')
    : undefined;

  useEffect(() => {
    if (isLoading || !transaction) return;

    const app = getTelegramApp();
    if (!app?.initData) {
      setState(States.ERROR);
      alert('ERROR: Missing Telegram WebApp init data');
      return;
    }

    let isCanceled = false;
    setState(States.LOADING);
    setError(undefined);
    setExtensionAddress(undefined);
    setActiveTelegramId(undefined);
    setEmulation(undefined);
    setAreActionsLoading(false);

    const opCode = getPayloadOpCode(transaction.payload);
    const shouldCheckActions = opCode === OpCode.SEND_ACTIONS;

    const resolveExtension = () => {
      if (!requestId) {
        setState(States.ERROR);
        alert('ERROR: Missing MFA request id');
        return;
      }

      // UX-only fail-fast from raw initData; the backend verifies the same initData before returning the transaction.
      const telegramId = getTelegramUserIdFromInitData(app.initData);

      if (isCanceled) return;

      if (!telegramId) {
        setState(States.ERROR);
        alert('ERROR: Missing Telegram WebApp user id');
        return;
      }

      setActiveTelegramId(telegramId);

      resolveExtensionAddress(transaction.address, telegramId).then((result) => {
        if (isCanceled) return;
        setExtensionAddress(result);
        setState(shouldCheckActions ? States.CHECKING : States.READY);
      }).catch(() => {
        if (!isCanceled) {
          setState(States.UNINSTALLED);
          setError(lang('This wallet is not linked to the current Telegram account.'));
        }
      });
    };
    resolveExtension();

    return () => {
      isCanceled = true;
    };
  }, [isLoading, lang, requestId, transaction]);

  useEffect(() => {
    if (!extensionAddress || !transaction || !activeTelegramId) return;

    let isCanceled = false;

    void (async () => {
      try {
        setEmulation(undefined);
        const opCode = getPayloadOpCode(transaction.payload);
        const shouldCheckActions = opCode === OpCode.SEND_ACTIONS;
        setAreActionsLoading(shouldCheckActions);

        if (shouldCheckActions) {
          await ensureMfaTokenInfoReady();
        }

        const result = await checkTransaction(
          activeTelegramId,
          transaction.payload,
          extensionAddress,
          transaction.address,
        );

        if (!isCanceled) {
          setEmulation(result);
          setAreActionsLoading(false);
          if (shouldCheckActions) {
            setState(States.READY);
          }
        }
      } catch (err: any) {
        if (isCanceled) return;

        setAreActionsLoading(false);
        setState(States.ERROR);
        alert(err);
      }
    })();

    return () => {
      isCanceled = true;
    };
  }, [activeTelegramId, extensionAddress, lang, transaction]);

  const onConfirmClicked = async () => {
    if (!extensionAddress || !requestId) return;

    setState(States.PROCESSING);

    try {
      const txHash = await sendActions(transaction!.payload, transaction!.signature, extensionAddress);
      await confirmTransaction(requestId, txHash);

      onConfirm();
    } catch (err: any) {
      if (err.message?.includes('703')) {
        alert('Error');
      }

      alert(`ERROR: ${err}`);
      setState(States.READY);
    }
  };

  return (
    <div className={buildClassName(commonStyles.container, styles.container)}>
      <AnimatedIconWithPreview
        className={commonStyles.sticker}
        play
        noLoop={false}
        nonInteractive
        size={ANIMATED_STICKER_MIDDLE_SIZE_PX}
        tgsUrl={ANIMATED_STICKERS_PATHS.bill}
        previewUrl={ANIMATED_STICKERS_PATHS.billPreview}
      />

      <div className={styles.title}>{title ?? '\u00A0'}</div>

      {(error || transactionError) && <div className={styles.error}>{error || transactionError}</div>}

      <div className={styles.preview}>
        {areActionsLoading ? (
          <DappSkeletonWithContent
            rows={actionSkeletonRows}
            shouldRenderHeader={false}
            shouldRenderOuterPadding={false}
          />
        ) : (
          <ActivityPreview
            activities={emulation?.activities}
            realFee={emulation?.realFee}
            feeToken={TONCOIN}
            tokensBySlug={tokensBySlug}
            swapTokensBySlug={swapTokensBySlug}
            appTheme={appTheme}
            nftsByAddress={nftsByAddress}
            currentAccountId={currentAccountId ?? ''}
            stakingStateByPool={stakingStateByPool}
            savedAddresses={savedAddresses}
            accounts={accounts}
            baseCurrency={baseCurrency}
            currencyRates={currencyRates}
            shouldHideStakingAnnualYield
          />
        )}
      </div>

      <UniversalButton
        isPrimary
        isActive={isActive && currentState !== States.ERROR && currentState !== States.UNINSTALLED && !transactionError}
        isLoading={isLoading || (
          !transactionError
          && currentState !== States.READY
          && currentState !== States.ERROR
          && currentState !== States.UNINSTALLED
        )}
        onClick={onConfirmClicked}
      >
        {lang('Confirm')}
      </UniversalButton>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountId = selectCurrentAccountId(global);
  const accountState = selectCurrentAccountState(global);
  const accounts = selectNetworkAccounts(global);

  return {
    tokensBySlug: global.tokenInfo.bySlug,
    swapTokensBySlug: global.swapTokenInfo?.bySlug,
    theme: global.settings.theme,
    baseCurrency: global.settings.baseCurrency,
    currencyRates: global.currencyRates,
    nftsByAddress: accountState?.nfts?.byAddress,
    currentAccountId: accountId,
    stakingStateByPool: accountId ? selectAccountStakingStatesByPool(global, accountId) : {},
    savedAddresses: accountState?.savedAddresses,
    accounts,
  };
})(Confirmation));

function getTelegramUserIdFromInitData(initData: string) {
  const user = new URLSearchParams(initData).get('user');
  if (!user) return undefined;

  try {
    const parsed = JSON.parse(user) as { id?: string | number };
    return parsed.id ? String(parsed.id) : undefined;
  } catch {
    return undefined;
  }
}

function getPayloadOpCode(payload: string) {
  return Cell.fromBase64(payload).beginParse().loadUint(32) as OpCode;
}
