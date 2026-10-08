import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import type { ConfirmationAsset, ConfirmationRecipient } from './helpers/confirmationHeader';

import { TONCOIN } from '../../config';
import {
  selectCurrentAccountId,
  selectIsGramDiamondEnabled,
  selectIsMultichainAccount,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { splitNftNumber } from '../../util/splitNftNumber';
import { getIsChainBadgeShown } from '../../util/tokens';

import useLang from '../../hooks/useLang';

import Image from '../ui/Image';
import WalletAvatar from '../ui/WalletAvatar';
import GramDiamond from './GramDiamond';
import HeroAmount from './HeroAmount';
import NftImage from './NftImage';
import TokenIcon from './TokenIcon';

import styles from './ConfirmationHeader.module.scss';

interface OwnProps {
  assets: ConfirmationAsset[];
  /** Shown in place of the assets when there are none */
  title?: string;
  /** The plural title of two or more assets */
  countLangKey?: keyof typeof COUNT_PLACEHOLDERS;
  subtitlePrefix?: string;
  recipient?: ConfirmationRecipient;
  dapp?: StoredDappConnection;
}

interface StateProps {
  isMultichainAccount: boolean;
  areChainBadgesShown?: boolean;
  isSensitiveDataHidden?: true;
  isGramDiamondEnabled: boolean;
}

const DAPP_ICON_FALLBACK_CLASS_NAME = buildClassName(styles.dappIconFallback, 'icon-laptop');
const COUNT_PLACEHOLDERS = {
  $many_transactions: 'count',
  '%amount% NFTs': 'amount',
} as const;
const MAX_STACK_SIZE = 10;
// Larger stacks overlap their icons twice as much, as on iOS
const LOOSE_STACK_MAX_SIZE = 3;
// The end of a dApp name stays visible when the name is truncated, as with middle truncation on iOS
const DAPP_NAME_TAIL_LENGTH = 6;

function ConfirmationHeader({
  assets,
  title,
  countLangKey,
  subtitlePrefix,
  recipient,
  dapp,
  isMultichainAccount,
  areChainBadgesShown,
  isSensitiveDataHidden,
  isGramDiamondEnabled,
}: OwnProps & StateProps) {
  const lang = useLang();
  const isPinPadLayout = getDoesUsePinPad();

  function renderIcon() {
    if (assets.length === 1) {
      const [asset] = assets;

      if (isGramDiamondEnabled && asset.type === 'token' && asset.token.slug === TONCOIN.slug) {
        return <GramDiamond className={styles.diamond} />;
      }

      return asset.type === 'token' ? (
        <TokenIcon
          token={asset.token}
          size="xxx-large"
          withChainIcon={isMultichainAccount && getIsChainBadgeShown(asset.token, areChainBadgesShown)}
        />
      ) : <NftImage url={asset.thumbnail} alt={asset.name} className={styles.nftImage} />;
    }

    return (
      <div className={buildClassName(styles.stack, assets.length > LOOSE_STACK_MAX_SIZE && styles.stack_dense)}>
        {assets.slice(0, MAX_STACK_SIZE).map((asset, index) => (
          <div key={index} className={styles.stackSlot}>
            {asset.type === 'token'
              ? <TokenIcon token={asset.token} size="xxx-large" iconClassName={styles.stackIcon} />
              : (
                <NftImage
                  url={asset.thumbnail}
                  alt={asset.name}
                  className={buildClassName(styles.nftImage, styles.stackIcon)}
                />
              )}
          </div>
        ))}
      </div>
    );
  }

  function renderTitle() {
    if (!assets.length) {
      return <div className={styles.title}>{title}</div>;
    }

    if (assets.length > 1) {
      const count = assets.length;
      const countNode = <span className={styles.countValue}>{count}</span>;

      return (
        <div className={buildClassName(styles.title, styles.secondary)}>
          {lang(countLangKey!, { [COUNT_PLACEHOLDERS[countLangKey!]]: countNode }, undefined, count)}
        </div>
      );
    }

    const [asset] = assets;
    if (asset.type === 'token') {
      const { token, amount } = asset;

      return (
        <HeroAmount
          value={toDecimal(amount, token.decimals)}
          decimals={token.decimals}
          suffix={token.symbol}
          isNegative
          isSensitiveDataHidden={isSensitiveDataHidden}
          className={styles.amount}
        />
      );
    }

    const { name, nftNumber } = splitNftNumber(asset.name || lang('NFT'));

    return (
      <div className={styles.title}>
        {name}
        {nftNumber && <span className={styles.secondary}> {nftNumber}</span>}
      </div>
    );
  }

  function renderSubtitle() {
    if (!recipient && !dapp) return undefined;

    return (
      <div className={styles.subtitle}>
        {subtitlePrefix && <span className={styles.subtitlePrefix}>{subtitlePrefix}</span>}
        {recipient?.type === 'wallet' && (
          <WalletAvatar
            title={recipient.name}
            accountId={recipient.accountId}
            imageUrl={recipient.imageUrl}
            className={styles.avatar}
          />
        )}
        {recipient && (
          <span className={styles.subtitleText}>
            {recipient.type === 'wallet' ? recipient.name : recipient.text}
          </span>
        )}
        {dapp && (
          <>
            <Image
              url={dapp.iconUrl}
              alt={dapp.name}
              forceLoaded
              className={styles.dappIcon}
              imageClassName={styles.dappIconImage}
              fallbackClassName={DAPP_ICON_FALLBACK_CLASS_NAME}
            />
            {renderDappName(dapp.name)}
          </>
        )}
      </div>
    );
  }

  return (
    <div
      className={buildClassName(
        styles.root,
        !assets.length && styles.root_noIcon,
        isPinPadLayout && styles.root_pinPad,
      )}
    >
      {assets.length > 0 && (
        <div className={buildClassName(styles.icon, isPinPadLayout && styles.icon_pinPad)}>
          {renderIcon()}
        </div>
      )}
      {renderTitle()}
      {renderSubtitle()}
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const currentAccountId = selectCurrentAccountId(global);
  const { areChainBadgesShown, isSensitiveDataHidden } = global.settings;

  return {
    isMultichainAccount: currentAccountId ? selectIsMultichainAccount(global, currentAccountId) : false,
    areChainBadgesShown,
    isSensitiveDataHidden,
    isGramDiamondEnabled: selectIsGramDiamondEnabled(global),
  };
})(ConfirmationHeader));

function renderDappName(name: string) {
  const characters = Array.from(name);
  if (characters.length <= DAPP_NAME_TAIL_LENGTH * 2) {
    return <span className={styles.subtitleText}>{name}</span>;
  }

  return (
    <span className={styles.dappName}>
      <span className={styles.subtitleText}>{characters.slice(0, -DAPP_NAME_TAIL_LENGTH).join('')}</span>
      <span className={styles.dappNameTail}>{characters.slice(-DAPP_NAME_TAIL_LENGTH).join('')}</span>
    </span>
  );
}
