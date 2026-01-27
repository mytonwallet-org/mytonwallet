import type { ApiLiquidStakingState } from '../../../api/types';
import type { AccountChain } from '../../types';

import {
  DEFAULT_STAKING_STATE,
  IS_CORE_WALLET,
  MTW_CARDS_COLLECTION,
  SWAP_API_VERSION,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
} from '../../../config';
import { areDeepEqual } from '../../../util/areDeepEqual';
import { buildCollectionByKey, unique } from '../../../util/iteratees';
import { callActionInNative } from '../../../util/multitab';
import { openUrl } from '../../../util/openUrl';
import { IS_DELEGATING_BOTTOM_SHEET, IS_IOS_APP } from '../../../util/windowEnvironment';
import { addActionHandler, setGlobal } from '../../index';
import {
  addNft,
  addUnorderedNfts,
  createAccount,
  removeNft,
  updateAccountChain,
  updateAccountSettingsBackgroundNft,
  updateAccountStaking,
  updateAccountState,
  updateBalances,
  updateCurrencyRates,
  updateNft,
  updateRestrictions,
  updateSettings,
  updateStakingDefault,
  updateSwapTokens,
  updateTokens,
  updateVesting,
  updateVestingInfo,
} from '../../reducers';
import {
  selectAccount,
  selectAccountNftByAddress,
  selectAccountSettings,
  selectAccountState,
  selectVestingPartsReadyToUnfreeze,
} from '../../selectors';

addActionHandler('apiUpdate', (global, actions, update) => {
  switch (update.type) {
    case 'updateBalances': {
      global = updateBalances(global, update.accountId, update.chain, update.balances);
      setGlobal(global);
      break;
    }

    case 'updateStaking': {
      const {
        accountId,
        states,
        totalProfit,
        shouldUseNominators,
      } = update;

      const stateById = buildCollectionByKey(states, 'id');

      global = updateStakingDefault(global, {
        ...stateById[DEFAULT_STAKING_STATE.id] as ApiLiquidStakingState,
        balance: 0n,
        unstakeRequestAmount: 0n,
        tokenBalance: 0n,
      });
      global = updateAccountStaking(global, accountId, {
        stateById,
        shouldUseNominators,
        totalProfit,
      });

      const { stakingId } = selectAccountState(global, accountId)?.staking ?? {};

      if (!stakingId) {
        const stateWithBiggestBalance = [...states].sort(
          (state0, state1) => Number(state1.balance - state0.balance),
        )[0];

        if (stateWithBiggestBalance && stateWithBiggestBalance.balance > 0n) {
          global = updateAccountStaking(global, accountId, {
            stakingId: stateWithBiggestBalance.id,
          });
        } else if (shouldUseNominators && stateById.nominators) {
          global = updateAccountStaking(global, accountId, {
            stakingId: stateById.nominators.id,
          });
        }
      }

      setGlobal(global);
      break;
    }

    case 'updateTokens': {
      const { tokens } = update;
      global = updateTokens(global, tokens, true);
      setGlobal(global);
      break;
    }

    case 'updateSwapTokens': {
      global = updateSwapTokens(global, update.tokens);
      setGlobal(global);

      break;
    }

    case 'updateCurrencyRates': {
      global = updateCurrencyRates(global, update.rates);
      setGlobal(global);
      break;
    }

    case 'updateNfts': {
      // `CustomizeWalletModal` is opened in a NBS before the nfts are updated, so we need to translate the update to the native side
      // to prevent infinite loading
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('apiUpdate', update);
      }
      const { accountId, collectionAddress } = update;
      const nfts = buildCollectionByKey(update.nfts, 'address');
      const currentNfts = selectAccountState(global, accountId)?.nfts;
      const newOrderedAddresses = Object.keys(nfts);

      const shouldAppend = !!collectionAddress;

      global = updateAccountState(global, accountId, {
        nfts: {
          ...currentNfts,
          byAddress: { ...nfts, ...currentNfts?.byAddress },
          orderedAddresses: unique(
            shouldAppend
              ? ([] as string[]).concat(currentNfts?.orderedAddresses ?? [], newOrderedAddresses)
              : ([] as string[]).concat(newOrderedAddresses, currentNfts?.orderedAddresses ?? []),
          ),
          isLoadedByAddress: {
            ...currentNfts?.isLoadedByAddress,
            ...(shouldAppend ? { [collectionAddress]: true } : {}),
          },
        },
      });

      if (!IS_CORE_WALLET) {
        update.nfts.forEach((nft) => {
          if (nft.collectionAddress === MTW_CARDS_COLLECTION) {
            global = updateAccountSettingsBackgroundNft(global, nft);
          }
        });
      }

      const hasTelegramGifts = update.nfts.some((nft) => nft.isTelegramGift);
      if (hasTelegramGifts) {
        actions.addCollectionTab({
          collectionAddress: TELEGRAM_GIFTS_SUPER_COLLECTION,
          isAuto: true,
        });
      }

      setGlobal(global);

      actions.checkCardNftOwnership();
      break;
    }

    case 'nftSent': {
      const { accountId, nftAddress, newOwnerAddress } = update;
      const sentNft = selectAccountNftByAddress(global, accountId, nftAddress);
      global = removeNft(global, accountId, nftAddress);

      if (sentNft?.collectionAddress === MTW_CARDS_COLLECTION) {
        sentNft.ownerAddress = newOwnerAddress;
        global = updateAccountSettingsBackgroundNft(global, sentNft);
      }
      setGlobal(global);

      actions.checkCardNftOwnership();
      break;
    }

    case 'nftReceived': {
      const { accountId, nft } = update;
      global = addNft(global, accountId, nft);
      setGlobal(global);

      if (!IS_CORE_WALLET) {
        actions.checkCardNftOwnership();
        const settings = selectAccountSettings(global, accountId);
        // If a user received an NFT card from the MyTonWallet collection, it is applied immediately.
        // But only if it is not already set.
        if (nft.collectionAddress === MTW_CARDS_COLLECTION && !settings?.cardBackgroundNft) {
          actions.setCardBackgroundNft({ nft });
          actions.installAccentColorFromNft({ nft });
        }
      }
      break;
    }

    case 'nftPutUpForSale': {
      const { accountId, nftAddress } = update;
      global = updateNft(global, accountId, nftAddress, {
        isOnSale: true,
      });
      setGlobal(global);
      break;
    }

    case 'updateAccount': {
      const { accountId, chain, domain, address, isMultisig } = update;
      const account = selectAccount(global, accountId);
      if (!account?.byChain[chain]) {
        break;
      }

      const chainUpdate: Partial<AccountChain> = {};
      if (address) {
        chainUpdate.address = address;
      }
      if (domain !== undefined) {
        chainUpdate.domain = domain || undefined;
      }
      if (isMultisig !== undefined) {
        chainUpdate.isMultisig = isMultisig || undefined;
      }
      global = updateAccountChain(global, accountId, chain, chainUpdate);
      setGlobal(global);
      break;
    }

    case 'updateConfig': {
      const {
        isLimited: isLimitedRegion,
        isCopyStorageEnabled,
        supportAccountsCount,
        countryCode,
        isAppUpdateRequired,
        swapVersion,
        seasonalTheme,
      } = update;

      const shouldRestrictSwapsAndOnOffRamp = (IS_IOS_APP && isLimitedRegion) || IS_CORE_WALLET;
      global = updateRestrictions(global, {
        isLimitedRegion,
        isSwapDisabled: shouldRestrictSwapsAndOnOffRamp,
        isOnRampDisabled: shouldRestrictSwapsAndOnOffRamp,
        isOffRampDisabled: shouldRestrictSwapsAndOnOffRamp,
        isNftBuyingDisabled: shouldRestrictSwapsAndOnOffRamp,
        isCopyStorageEnabled,
        supportAccountsCount,
        countryCode,
      });
      global = {
        ...global,
        isAppUpdateRequired: IS_CORE_WALLET ? undefined : isAppUpdateRequired,
        swapVersion: swapVersion ?? SWAP_API_VERSION,
        seasonalTheme,
      };
      setGlobal(global);
      break;
    }

    case 'updateWalletVersions': {
      if (IS_DELEGATING_BOTTOM_SHEET) {
        callActionInNative('apiUpdateWalletVersions', update);
      }

      actions.apiUpdateWalletVersions(update);
      break;
    }

    case 'openUrl': {
      void openUrl(update.url, { isExternal: update.isExternal, title: update.title, subtitle: update.subtitle });
      break;
    }

    case 'requestReconnectApi': {
      actions.initApi();
      break;
    }

    case 'incorrectTime': {
      if (!global.isIncorrectTimeNotificationReceived) {
        actions.showIncorrectTimeError();
      }
      break;
    }

    case 'updateVesting': {
      const { accountId, vestingInfo } = update;
      const unfreezeRequestedIds = selectVestingPartsReadyToUnfreeze(global, accountId);
      global = updateVestingInfo(global, accountId, vestingInfo);
      const newUnfreezeRequestedIds = selectVestingPartsReadyToUnfreeze(global, accountId);
      if (!areDeepEqual(unfreezeRequestedIds, newUnfreezeRequestedIds)) {
        global = updateVesting(global, accountId, { unfreezeRequestedIds: undefined });
      }
      setGlobal(global);
      break;
    }

    case 'updatingStatus': {
      const { kind, accountId, isUpdating } = update;
      const key = kind === 'balance' ? 'balanceUpdateStartedAt' : 'activitiesUpdateStartedAt';
      const accountState = selectAccountState(global, accountId);
      if (isUpdating && accountState?.[key]) break;

      global = updateAccountState(global, accountId, {
        [key]: isUpdating ? Date.now() : undefined,
      });

      // Set `isAppReady` when balance loading is complete
      if (!accountState?.isAppReady && kind === 'balance' && !isUpdating) {
        global = updateAccountState(global, accountId, { isAppReady: true });
      }

      setGlobal(global);
      break;
    }

    // Should be removed in future versions
    case 'migrateCoreApplication': {
      const {
        accountId,
        isTestnet,
        address,
        secondAddress,
        secondAccountId,
        isTonProxyEnabled,
        isTonMagicEnabled,
      } = update;

      global = updateSettings(global, { isTestnet });
      global = createAccount({
        global,
        accountId,
        type: 'mnemonic',
        byChain: { ton: { address } },
      });
      global = createAccount({
        global,
        accountId: secondAccountId,
        type: 'mnemonic',
        byChain: { ton: { address: secondAddress } },
        network: isTestnet ? 'mainnet' : 'testnet', // Second account should be created on opposite network
      });
      setGlobal(global);

      // Run the application only after the post-migration GlobalState has been applied
      requestAnimationFrame(() => {
        actions.tryAddNotificationAccount({ accountId });
        actions.switchAccount({ accountId, newNetwork: isTestnet ? 'testnet' : 'mainnet' });
        actions.afterSignIn();

        if (isTonMagicEnabled) {
          actions.toggleTonMagic({ isEnabled: true });
        }
        if (isTonProxyEnabled) {
          actions.toggleTonProxy({ isEnabled: true });
        }
      });
      break;
    }

    case 'updateAccountConfig': {
      const { accountConfig, accountId } = update;
      global = updateAccountState(global, accountId, { config: accountConfig });
      setGlobal(global);
      break;
    }

    case 'updateAccountDomainData': {
      const {
        accountId,
        expirationByAddress,
        linkedAddressByAddress,
        nfts: updatedNfts,
      } = update;
      const nfts = selectAccountState(global, accountId)?.nfts || { byAddress: {} };

      global = updateAccountState(global, accountId, {
        nfts: {
          ...nfts,
          dnsExpiration: expirationByAddress,
          linkedAddressByAddress,
        },
      });
      global = addUnorderedNfts(global, accountId, updatedNfts);
      setGlobal(global);
      break;
    }
  }
});
