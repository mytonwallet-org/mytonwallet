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
  selectAccountStakingStatesBySlug,
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
  stakingStateBySlug: Record<string, ApiStakingState>;
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
  stakingStateBySlug,
  savedAddresses,
  accounts,
  onConfirm,
}: OwnProps & StateProps) {
  const [currentState, setState] = useState<States>(States.LOADING);
  const [extensionAddress, setExtensionAddress] = useState<Address | undefined>(undefined);
  const [emulation, setEmulation] = useState<Pick<ApiEmulationResult, 'activities' | 'realFee'> | undefined>(
    undefined,
  );
  const [areActionsLoading, setAreActionsLoading] = useState(false);

  useEffect(() => {
    if (isLoading || !transaction) return;

    const telegramId = getTelegramApp()?.initDataUnsafe.user?.id;
    if (!telegramId) {
      setState(States.ERROR);
      return;
    }

    let isCanceled = false;
    setState(States.LOADING);
    setExtensionAddress(undefined);
    setEmulation(undefined);
    setAreActionsLoading(false);

    const opCode = getPayloadOpCode(transaction.payload);
    const shouldCheckActions = opCode === OpCode.SEND_ACTIONS;

    resolveExtensionAddress(transaction.address, String(telegramId)).then(
      (result) => {
        if (isCanceled) return;
        setExtensionAddress(result);
        setState(shouldCheckActions ? States.CHECKING : States.READY);
      },
    ).catch(() => {
      if (!isCanceled) setState(States.UNINSTALLED);
    });

    return () => {
      isCanceled = true;
    };
  }, [isLoading, transaction]);

  useEffect(() => {
    if (!extensionAddress || !transaction) return;

    const telegramId = getTelegramApp()!.initDataUnsafe.user?.id;
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
          String(telegramId),
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
  }, [extensionAddress, transaction]);

  const lang = useLang();
  const appTheme = useAppTheme(theme);

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

      <div className={styles.title}>{lang('Is it all ok?')}</div>

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
            stakingStateBySlug={stakingStateBySlug}
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
        isActive={isActive && currentState !== States.ERROR}
        isLoading={isLoading || currentState !== States.READY}
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
    stakingStateBySlug: accountId ? selectAccountStakingStatesBySlug(global, accountId) : {},
    savedAddresses: accountState?.savedAddresses,
    accounts,
  };
})(Confirmation));

function getPayloadOpCode(payload: string) {
  return Cell.fromBase64(payload).beginParse().loadUint(32) as OpCode;
}
