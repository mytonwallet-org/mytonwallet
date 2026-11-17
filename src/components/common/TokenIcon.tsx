import React, { memo, type TeactNode } from '../../lib/teact/teact';

import type { ApiSwapAsset, ApiToken } from '../../api/types';
import type { UserSwapToken, UserToken } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import getChainNetworkIcon from '../../util/swap/getChainNetworkIcon';
import { getIsNativeStakedToken, getIsNativeToken, getIsRwaStockToken } from '../../util/tokens';

import useFlag from '../../hooks/useFlag';

import styles from './TokenIcon.module.scss';

interface OwnProps {
  token: UserToken | UserSwapToken | ApiSwapAsset | ApiToken;
  withChainIcon?: boolean;
  size?: 'x-small' | 'small' | 'middle' | 'large' | 'xx-large' | 'xxx-large';
  className?: string;
  iconClassName?: string;
  children?: TeactNode;
}

function TokenIcon({
  token, size, withChainIcon, className, iconClassName, children,
}: OwnProps) {
  const { symbol, image, chain, slug } = token;
  const [isLoadingError, markLoadingError] = useFlag();
  const isNativeToken = getIsNativeToken(slug);
  const isNativeTokenStaking = getIsNativeStakedToken(slug);
  const shouldRenderImage = Boolean(image) && !isLoadingError;
  const isSquare = getIsRwaStockToken(token);
  const shapeClassName = isSquare ? styles.square : styles.circle;
  const shouldRenderChainIcon = Boolean(withChainIcon && !isNativeToken && !isNativeTokenStaking && chain);
  const iconFullClassName = buildClassName(
    styles.icon,
    size && styles[size],
    shapeClassName,
    shouldRenderChainIcon && styles.withChainIcon,
    iconClassName,
  );

  function renderImage() {
    const img = (
      <img
        key={image}
        src={image}
        data-account-crossfade-image
        alt={symbol}
        className={isSquare ? styles.squareImage : iconFullClassName}
        draggable={false}
        onError={markLoadingError}
      />
    );

    // The image of a stock goes on black, and the icon clips the image with its black at once
    return isSquare ? <div className={iconFullClassName}>{img}</div> : img;
  }

  function renderDefaultIcon() {
    return (
      <div className={buildClassName(iconFullClassName, styles.fallbackIcon)}>
        {symbol.slice(0, 1)}
      </div>
    );
  }

  return (
    <div
      className={buildClassName(
        styles.wrapper,
        size && styles[size],
        className,
      )}
    >
      {shouldRenderImage ? renderImage() : renderDefaultIcon()}
      {shouldRenderChainIcon && (
        <img
          src={getChainNetworkIcon(chain)}
          data-account-crossfade-image
          alt=""
          className={styles.blockchainIcon}
          draggable={false}
        />
      )}
      {children}
    </div>
  );
}

export default memo(TokenIcon);
