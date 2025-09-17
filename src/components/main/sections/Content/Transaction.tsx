import type { Ref, RefObject } from 'react';
import type { TeactNode } from '../../../../lib/teact/teact';
import React, { memo, useMemo } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import type {
  ApiBaseCurrency,
  ApiCurrencyRates,
  ApiNft,
  ApiTokenWithPrice,
  ApiTransactionActivity,
  ApiTransactionType,
  ApiYieldType,
} from '../../../../api/types';
import type { Account, AppTheme, SavedAddress } from '../../../../global/types';
import type { Color as PendingIndicatorColor } from './ActivityStatusIcon';

import {
  FRACTION_DIGITS,
  NFT_MARKETPLACE_TITLES,
  SWAP_DEX_LABELS,
  TONCOIN,
  TRANSACTION_ADDRESS_SHIFT,
  WHOLE_PART_DELIMITER,
} from '../../../../config';
import {
  DNS_TRANSACTION_TYPES,
  getIsActivityPendingForUser,
  getTransactionAmountDisplayMode,
  getTransactionTitle,
  isScamTransaction,
  shouldShowTransactionAddress,
  shouldShowTransactionAnnualYield,
  shouldShowTransactionComment,
  STAKING_TRANSACTION_TYPES,
} from '../../../../util/activities';
import { bigintAbs } from '../../../../util/bigint';
import buildClassName from '../../../../util/buildClassName';
import { formatTime } from '../../../../util/dateFormat';
import { toDecimal } from '../../../../util/decimals';
import { getDnsDomainZone } from '../../../../util/dns';
import { formatBaseCurrencyAmount, formatCurrencyExtended } from '../../../../util/formatNumber';
import { getLocalAddressName } from '../../../../util/getLocalAddressName';
import getPseudoRandomNumber from '../../../../util/getPseudoRandomNumber';
import { vibrate } from '../../../../util/haptics';
import { shortenAddress } from '../../../../util/shortenAddress';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import TokenIcon from '../../../common/TokenIcon';
import Button from '../../../ui/Button';
import SensitiveData from '../../../ui/SensitiveData';
import ActivityStatusIcon from './ActivityStatusIcon';

import styles from './Activity.module.scss';

import scamImg from '../../../../assets/scam.svg';

type OwnProps = {
  ref?: Ref<HTMLElement>;
  tokensBySlug: Record<string, ApiTokenWithPrice>;
  transaction: ApiTransactionActivity;
  isLast?: boolean;
  isActive?: boolean;
  withChainIcon?: boolean;
  annualYield: number | undefined;
  yieldType: ApiYieldType | undefined;
  appTheme: AppTheme;
  savedAddresses: SavedAddress[] | undefined;
  doesNftExist?: boolean;
  isSensitiveDataHidden?: boolean;
  isFuture?: boolean;
  accounts: Record<string, Account> | undefined;
  currentAccountId: string;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  onClick?: (id: string) => void;
};

const TRANSACTION_HEIGHT = 4; // rem
const NFT_EXTRA_HEIGHT = 3.875; // rem
const COMMENT_EXTRA_HEIGHT = 2.375; // rem
const SUBHEADER_RELEASE_HEIGHT = 1.25; // rem

const OUT_TRANSACTION_TYPES = new Set<ApiTransactionType>([
  undefined, 'unstakeRequest', 'nftTrade', 'auctionBid', 'liquidityDeposit',
]);

function Transaction({
  ref,
  tokensBySlug,
  transaction,
  isActive,
  annualYield,
  yieldType,
  savedAddresses,
  isLast,
  appTheme,
  withChainIcon,
  doesNftExist,
  isSensitiveDataHidden,
  isFuture,
  accounts,
  currentAccountId,
  baseCurrency,
  currencyRates,
  onClick,
}: OwnProps) {
  const { openNftAttributesModal } = getActions();
  const lang = useLang();

  const {
    id,
    amount,
    fromAddress,
    toAddress,
    timestamp,
    comment,
    encryptedComment,
    isIncoming,
    type,
    metadata,
    slug,
    nft,
    extra,
    status,
  } = transaction;

  const isStaking = STAKING_TRANSACTION_TYPES.has(type);
  const isDnsOperation = DNS_TRANSACTION_TYPES.has(type);

  const token = tokensBySlug[slug];
  const { chain } = token || {};
  const address = isIncoming ? fromAddress : toAddress;
  const localAddressName = useMemo(() => {
    if (!chain) return undefined;

    return getLocalAddressName({
      address,
      chain,
      currentAccountId,
      accounts,
      savedAddresses,
    });
  }, [accounts, address, chain, currentAccountId, savedAddresses]);
  const addressName = localAddressName || metadata?.name;
  const dnsIconText = useMemo(() => isDnsOperation ? getDnsIconText(nft) : '', [isDnsOperation, nft]);
  const amountCols = useMemo(() => getPseudoRandomNumber(5, 13, timestamp.toString()), [timestamp]);
  const attachmentsTakeSubheader = shouldAttachmentTakeSubheader(transaction, isFuture);
  const isNoSubheaderLeft = getIsNoSubheaderLeft(transaction, isFuture);
  const titleTense = isFuture || status === 'failed' ? 'future' : 'past';

  let operationColorClass: string | undefined;
  let pendingIndicatorColor: PendingIndicatorColor = 'Gray';
  if (status === 'failed' || type === 'burn') {
    operationColorClass = styles.colorNegative;
    pendingIndicatorColor = 'Red';
  } else if (isIncoming) {
    operationColorClass = styles.colorIn;
    pendingIndicatorColor = 'Green';
  } else if (type === 'stake') {
    operationColorClass = styles.colorStake;
    pendingIndicatorColor = 'PurpleWhite';
  } else if (OUT_TRANSACTION_TYPES.has(type)) {
    operationColorClass = styles.colorOut;
    pendingIndicatorColor = 'Blue';
  }

  if (status === 'pending') {
    pendingIndicatorColor = 'Orange';
  }

  const handleNftClick = useLastCallback((event: React.MouseEvent) => {
    event.stopPropagation();

    void vibrate();
    openNftAttributesModal({ nft: nft! });
  });

  function renderNft() {
    return (
      <div
        className={buildClassName(
          styles.attachment,
          styles.nft,
          !doesNftExist && styles.nonInteractive,
          'transaction-nft',
        )}
        onClick={doesNftExist ? handleNftClick : undefined}
        data-nft-address={nft?.address}
        data-tx-id={id}
      >
        <img src={nft!.thumbnail} alt={nft!.name} className={styles.nftImage} />
        <div className={styles.nftData}>
          <div className={styles.nftName}>{nft!.name}</div>
          <div className={styles.nftCollection}>{nft!.collectionName}</div>
        </div>
      </div>
    );
  }

  function renderComment() {
    const className = buildClassName(
      styles.attachment,
      styles.comment,
      !isIncoming && styles.outgoing,
      operationColorClass,
    );

    return (
      <div className={className}>
        {encryptedComment && <i className={buildClassName(styles.commentIcon, 'icon-lock')} aria-hidden />}
        {encryptedComment ? <i>{lang('Encrypted Message')}</i> : comment}
      </div>
    );
  }

  function renderIcon() {
    let iconName: string;
    if (isStaking) {
      iconName = 'icon-earn';
    } else if (type === 'callContract' || type === 'contractDeploy') {
      iconName = 'icon-cog';
    } else if (isDnsOperation) {
      iconName = buildClassName('rounded-font', styles.dnsIcon);
    } else if (type === 'mint') {
      iconName = 'icon-magic-wand';
    } else if (type === 'burn') {
      iconName = 'icon-fire';
    } else if (type === 'auctionBid') {
      iconName = 'icon-auction-alt';
    } else if (type === 'nftTrade') {
      iconName = isIncoming ? 'icon-tag' : 'icon-purchase';
    } else if (type === 'liquidityDeposit') {
      iconName = 'icon-can-in';
    } else if (type === 'liquidityWithdraw') {
      iconName = 'icon-can-out';
    } else if (isIncoming) {
      iconName = 'icon-receive-alt';
    } else {
      iconName = 'icon-send-alt';
    }

    return (
      <i className={buildClassName(styles.icon, iconName, operationColorClass)} aria-hidden>
        {isDnsOperation && (
          <span style={isDnsOperation ? `font-size: ${Math.min(1, 4 / dnsIconText.length) * 100}%` : undefined}>
            {dnsIconText}
          </span>
        )}
        <ActivityStatusIcon
          isPending={getIsActivityPendingForUser(transaction)}
          isError={status === 'failed'}
          color={pendingIndicatorColor}
          appTheme={appTheme}
        />
      </i>
    );
  }

  function renderAmount() {
    const amountDisplayMode = getTransactionAmountDisplayMode(transaction);
    const noSign = amountDisplayMode === 'noSign';

    if (amountDisplayMode === 'hide') {
      return;
    }

    return (
      <SensitiveData
        isActive={isSensitiveDataHidden}
        cols={amountCols}
        rows={2}
        cellSize={8}
        align="right"
        contentClassName={buildClassName(
          styles.amount,
          operationColorClass !== styles.colorOut && operationColorClass,
        )}
      >
        {formatCurrencyExtended(
          toDecimal(noSign ? bigintAbs(amount) : amount, token?.decimals ?? FRACTION_DIGITS),
          token?.symbol || TONCOIN.symbol,
          noSign,
          undefined,
          !isIncoming,
        )}
        {token && <TokenIcon token={token} size="x-small" className={styles.amountTokenIcon} />}
      </SensitiveData>
    );
  }

  function renderBaseCurrencyAmount() {
    if (getTransactionAmountDisplayMode(transaction) === 'hide' || !token) {
      return undefined;
    }

    return (
      <SensitiveData
        isActive={isSensitiveDataHidden}
        cols={Math.round(3 + (amountCols - 5) / 3)}
        rows={2}
        cellSize={8}
        align="right"
      >
        {formatBaseCurrencyAmount(amount, baseCurrency, token, currencyRates)}
      </SensitiveData>
    );
  }

  function renderAddressAndDate() {
    const children: TeactNode[] = [];
    const delimiter = `${WHOLE_PART_DELIMITER}∙${WHOLE_PART_DELIMITER}`;

    if (transaction.status === 'failed') {
      children.push(delimiter, lang('Failed'));
    }

    if (shouldShowTransactionAddress(transaction).includes('list')) {
      const dexName = extra?.dex && SWAP_DEX_LABELS[extra.dex];
      const marketplaceName = extra?.marketplace && NFT_MARKETPLACE_TITLES[extra.marketplace];

      children.push(delimiter, lang(
        (dexName || marketplaceName) ? '$transaction_on' : isIncoming ? '$transaction_from' : '$transaction_to',
        {
          address: (
            <span className={styles.subheaderHighlight}>
              {withChainIcon && Boolean(chain) && (
                <i
                  className={buildClassName(styles.chainIcon, `icon-chain-${chain.toLowerCase()}`)}
                  aria-label={chain}
                />
              )}
              {dexName || marketplaceName || addressName || shortenAddress(address, TRANSACTION_ADDRESS_SHIFT)}
            </span>
          ),
        },
      ));
    }

    if (shouldShowTransactionAnnualYield(transaction)) {
      children.push(delimiter, lang('at %annual_yield%', {
        annual_yield: <span className={styles.subheaderHighlight}>{yieldType} {annualYield}%</span>,
      }));
    }

    if (!isFuture) {
      children.push(delimiter, formatTime(timestamp));
    }

    // Warning! Keep this function result in sync with `getIsNoSubheaderLeft`
    return (
      <div className={styles.date}>
        {children.slice(1)}
      </div>
    );
  }

  return (
    <Button
      ref={ref as RefObject<HTMLButtonElement>}
      className={buildClassName(
        styles.item,
        isLast && styles.itemLast,
        isActive && styles.active,
        onClick && styles.interactive,
        attachmentsTakeSubheader === 'full' ? styles.attachmentsInFullSubheader
          : attachmentsTakeSubheader === 'left' ? styles.attachmentsInLeftSubheader : undefined,
      )}
      onClick={onClick && (() => onClick(id))}
      isSimple
    >
      {renderIcon()}
      <div className={styles.header}>
        <div
          className={buildClassName(
            styles.operationName,
            isNoSubheaderLeft && attachmentsTakeSubheader === 'none' && styles.atMiddle,
          )}
        >
          {getTransactionTitle(transaction, titleTense, lang)}
          {isScamTransaction(transaction) && <img src={scamImg} alt={lang('Scam')} className={styles.scamImage} />}
        </div>
        {renderAmount()}
      </div>
      <div className={styles.subheader}>
        {renderAddressAndDate()}
        {renderBaseCurrencyAmount()}
      </div>
      {nft && renderNft()}
      {shouldShowTransactionComment(transaction) && renderComment()}
    </Button>
  );
}

export default memo(Transaction);

export function getTransactionHeight(transaction: ApiTransactionActivity, isFuture?: boolean) {
  return TRANSACTION_HEIGHT
    + (transaction.nft ? NFT_EXTRA_HEIGHT : 0)
    + (shouldShowTransactionComment(transaction) ? COMMENT_EXTRA_HEIGHT : 0)
    - (shouldAttachmentTakeSubheader(transaction, isFuture) !== 'none' ? SUBHEADER_RELEASE_HEIGHT : 0);
}

function shouldAttachmentTakeSubheader(
  transaction: ApiTransactionActivity,
  isFuture?: boolean,
): 'none' | 'left' | 'full' {
  if (!transaction.nft && !shouldShowTransactionComment(transaction)) {
    return 'none';
  }

  if (!getIsNoSubheaderLeft(transaction, isFuture)) {
    return 'none'; // The attachment won't fit in the right slot, because the left subheader is too wide
  }

  if (getIsNoSubheaderRight(transaction)) {
    return 'full';
  }

  const isAttachmentOnTheLeft = transaction.nft || transaction.isIncoming;
  return isAttachmentOnTheLeft ? 'left' : 'none';
}

function getIsNoSubheaderLeft(transaction: ApiTransactionActivity, isFuture?: boolean) {
  return isFuture
    && transaction.status !== 'failed'
    && !shouldShowTransactionAddress(transaction).includes('list')
    && !shouldShowTransactionAnnualYield(transaction);
}

function getIsNoSubheaderRight(transaction: ApiTransactionActivity) {
  return getTransactionAmountDisplayMode(transaction) === 'hide';
}

function getDnsIconText(nft: ApiNft | undefined) {
  if (nft?.name) {
    const resolved = getDnsDomainZone(nft.name);
    if (resolved) {
      return `.${resolved.zone.suffixes[0]}`;
    }
  }

  return 'DNS';
}
