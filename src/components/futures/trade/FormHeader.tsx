import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsMarketAsset, ApiPerpsQuote } from '../../../api/types';

import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectHasMultipleAccounts,
  selectHasOtherPerpsAccount,
} from '../../../global/selectors';
import {
  formatPerpsFeeEstimate,
  formatPerpsFundingPercent,
  formatPerpsMoney,
  formatPerpsNetworkFee,
} from '../helpers/formatPerps';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import TradeHeader from '../../swap/TradeHeader';
import FeesMenu from './FeesMenu';

import styles from './FormHeader.module.scss';

interface OwnProps {
  title: string;
  /** The market of the trade. It is absent once the market leaves the catalogue. */
  asset?: ApiPerpsMarketAsset;
  /** The previewed order, whose fees the menu shows */
  preview?: ApiPerpsQuote;
  isEdit?: boolean;
}

interface StateProps {
  accountId?: string;
  accountTitle?: string;
  hasMultipleAccounts: boolean;
  hasOtherPerpsAccount: boolean;
}

/** The header of the trade forms: the account, the title, the market price, the fees menu and the close button */
function FormHeader({
  title, asset, preview, isEdit, accountId, accountTitle, hasMultipleAccounts, hasOtherPerpsAccount,
}: OwnProps & StateProps) {
  const { cancelPerpsTrade, setPerpsTradeStep } = getActions();
  const lang = useLang();

  const handleAccountClick = useLastCallback(() => {
    setPerpsTradeStep({ step: 'selectAccount' });
  });

  // The quote carries a fresher price than the catalogue
  const markPrice = preview?.markPrice ?? asset?.context.markPx;

  return (
    <TradeHeader
      accountId={accountId}
      accountTitle={accountTitle}
      hasMultipleAccounts={hasMultipleAccounts}
      title={(
        <div className={styles.title}>
          <span className={styles.titleText}>{title}</span>
          {Number(markPrice) > 0 && (
            <span className={styles.subtitle}>
              {lang('$token_price_value', { value: formatPerpsMoney(markPrice) })}
            </span>
          )}
        </div>
      )}
      menu={asset && (
        <FeesMenu
          // An order paid from the Hyperliquid balance crosses no bridge
          bridgeFee={preview && preview.funding !== 'balance'
            ? formatPerpsFeeEstimate(preview.estimatedFees?.bridge ?? preview.bridgeFee)
            : undefined}
          tradingFee={preview?.estimatedFees && formatPerpsFeeEstimate(preview.estimatedFees.trading)}
          fundingRate={formatPerpsFundingPercent(asset)}
          networkFee={preview && formatPerpsNetworkFee(preview)}
          isEdit={isEdit}
        />
      )}
      className={styles.root}
      onAccountClick={!isEdit && hasOtherPerpsAccount ? handleAccountClick : undefined}
      onClose={cancelPerpsTrade}
    />
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    accountId: selectCurrentAccountId(global),
    accountTitle: selectCurrentAccount(global)?.title,
    hasMultipleAccounts: selectHasMultipleAccounts(global),
    hasOtherPerpsAccount: selectHasOtherPerpsAccount(global),
  };
})(FormHeader));
