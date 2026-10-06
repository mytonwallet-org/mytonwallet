import React, { memo, useMemo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { Account, GlobalState, SavedAddress, UserToken } from '../../global/types';
import type { ConfirmationAsset } from '../common/helpers/confirmationHeader';

import { selectCurrentAccountId, selectCurrentAccountState, selectNetworkAccounts } from '../../global/selectors';
import { getChainBySlug } from '../../util/tokens';
import { getTransferRecipient } from '../common/helpers/confirmationHeader';

import useLang from '../../hooks/useLang';

import ConfirmationHeader from '../common/ConfirmationHeader';

interface OwnProps {
  transfer: GlobalState['currentTransfer'];
  token?: UserToken;
  isBurning?: boolean;
}

interface StateProps {
  currentAccountId: string;
  accounts?: Record<string, Account>;
  savedAddresses?: SavedAddress[];
}

function TransferConfirmationHeader({
  transfer: {
    amount, toAddress, toAddressName, tokenSlug, nfts,
  },
  token,
  isBurning,
  currentAccountId,
  accounts,
  savedAddresses,
}: OwnProps & StateProps) {
  const lang = useLang();

  const assets = useMemo((): ConfirmationAsset[] => {
    if (nfts?.length) {
      return nfts.map(({ name, thumbnail }) => ({ type: 'nft', name, thumbnail }));
    }

    return token && amount !== undefined ? [{ type: 'token', token, amount }] : [];
  }, [amount, nfts, token]);

  const recipient = useMemo(() => {
    if (isBurning || !toAddress) return undefined;

    return getTransferRecipient({
      address: toAddress,
      addressName: toAddressName,
      chain: nfts?.length ? nfts[0].chain : getChainBySlug(tokenSlug),
      currentAccountId,
      accounts,
      savedAddresses,
    });
  }, [accounts, currentAccountId, isBurning, nfts, savedAddresses, toAddress, toAddressName, tokenSlug]);

  return (
    <ConfirmationHeader
      assets={assets}
      countLangKey="%amount% NFTs"
      subtitlePrefix={recipient ? lang('Send to') : undefined}
      recipient={recipient}
    />
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    currentAccountId: selectCurrentAccountId(global)!,
    accounts: selectNetworkAccounts(global),
    savedAddresses: selectCurrentAccountState(global)?.savedAddresses,
  };
})(TransferConfirmationHeader));
