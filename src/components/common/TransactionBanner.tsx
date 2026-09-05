import type { TeactNode } from '../../lib/teact/teact';
import { useMemo } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { ApiSwapAsset, ApiToken } from '../../api/types';
import type { UserSwapToken, UserToken } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { compact, unique } from '../../util/iteratees';
import getChainNetworkIcon from '../../util/swap/getChainNetworkIcon';
import { getIsNativeToken } from '../../util/tokens';

import useLang from '../../hooks/useLang';

import TokenIcon from './TokenIcon';

import styles from './TransactionBanner.module.scss';

interface OwnProps {
  tokenIn?: UserToken | UserSwapToken | ApiSwapAsset | ApiToken;
  imageUrl?: string | string[];
  /** Keeps the NFT presentation when every `imageUrl` is empty: a placeholder instead of the `tokenIn` icon */
  withNftPlaceholder?: boolean;
  text?: string | TeactNode[];
  withChainIcon?: boolean;
  tokenOut?: UserToken | UserSwapToken | ApiSwapAsset | ApiToken;
  secondText?: string;
  color?: 'purple' | 'green';
  className?: string;
  textClassName?: string;
  isTextHidden?: boolean;
}

function TransactionBanner({
  tokenIn,
  imageUrl,
  withNftPlaceholder,
  text,
  withChainIcon,
  tokenOut,
  secondText,
  color,
  className,
  textClassName,
  isTextHidden,
}: OwnProps) {
  const lang = useLang();

  const fullClassName = buildClassName(
    styles.root,
    color && styles[color],
    tokenOut && styles.twoIcons,
    className,
  );

  const imageUrls = useMemo(() => {
    return compact(unique(Array.isArray(imageUrl) ? imageUrl : [imageUrl]));
  }, [imageUrl]);

  const isNftTransaction = imageUrls.length > 0 || withNftPlaceholder;

  function renderNftIcon() {
    return (
      <div className={buildClassName(styles.nftIcon, Array.isArray(imageUrl) && imageUrl.length > 1 && styles.stacked)}>
        {imageUrls.length ? imageUrls.map((image) => (
          <img src={image} alt="" key={image} className={styles.image} />
        )) : (
          <div className={buildClassName(styles.image, styles.imageNoData)} />
        )}
        {withChainIcon && tokenIn?.chain && tokenIn.slug && !getIsNativeToken(tokenIn.slug) && (
          <img
            src={getChainNetworkIcon(tokenIn.chain)}
            alt=""
            className={styles.chainIcon}
            draggable={false}
          />
        )}
      </div>
    );
  }

  return (
    <div className={fullClassName}>
      {tokenIn && !isNftTransaction && (
        <TokenIcon
          token={tokenIn}
          withChainIcon={withChainIcon}
          size="small"
        />
      )}
      {isNftTransaction && renderNftIcon()}
      {!isTextHidden && (
        <span className={buildClassName(styles.text, textClassName)}>
          {secondText
            ? text
              ? (
                lang('%amount% to %address%', {
                  amount: (
                    <span className={buildClassName(styles.bold, isNftTransaction && styles.nftTitle)}>
                      {text}
                    </span>
                  ),
                  address: <span className={buildClassName(styles.bold, styles.address)}>{secondText}</span>,
                })
              )
              : lang('$transaction_to', { address: <span className={styles.bold}>{secondText}</span> })
            : <span className={styles.bold}>{text}</span>}
        </span>
      )}
      {tokenOut && (
        <TokenIcon
          token={tokenOut}
          withChainIcon={withChainIcon}
          size="small"
        />
      )}
    </div>
  );
}

export default memo(TransactionBanner);
