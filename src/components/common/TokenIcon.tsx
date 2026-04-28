import React, { memo, type TeactNode } from '../../lib/teact/teact';

import type { ApiSwapAsset, ApiToken } from '../../api/types';
import type { UserSwapToken, UserToken } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import getChainNetworkIcon from '../../util/swap/getChainNetworkIcon';
import { getIsNativeStakedToken, getIsNativeToken } from '../../util/tokens';

import useFlag from '../../hooks/useFlag';

import styles from './TokenIcon.module.scss';

interface OwnProps {
  token: UserToken | UserSwapToken | ApiSwapAsset | ApiToken;
  withChainIcon?: boolean;
  size?: 'x-small' | 'small' | 'middle' | 'large' | 'x-large';
  className?: string;
  iconClassName?: string;
  children?: TeactNode;
}

function TokenIcon({
  token, size, withChainIcon, className, iconClassName, children,
}: OwnProps) {
  const { symbol, image, chain, slug } = token;
  const [isLoadingError, markLoadingError] = useFlag(false);
  const isNativeToken = getIsNativeToken(slug);
  const isNativeTokenStaking = getIsNativeStakedToken(slug);

  function renderDefaultIcon() {
    return (
      <div className={buildClassName(styles.icon, size && styles[size], iconClassName, styles.fallbackIcon)}>
        {symbol.slice(0, 1)}
      </div>
    );
  }

  return (
    <div className={buildClassName(styles.wrapper, className)}>
      {
        !isLoadingError ? (
          <img
            src={image}
            alt={symbol}
            className={buildClassName(styles.icon, size && styles[size], iconClassName)}
            draggable={false}
            onError={markLoadingError}
          />
        ) : renderDefaultIcon()
      }
      {withChainIcon && !isNativeToken && !isNativeTokenStaking && chain && (
        <img
          src={getChainNetworkIcon(chain)}
          alt=""
          className={buildClassName(styles.blockchainIcon, size && styles[size])}
          draggable={false}
        />
      )}
      {children}
    </div>
  );
}

export default memo(TokenIcon);
