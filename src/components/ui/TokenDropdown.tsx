import React, { memo, useMemo } from '../../lib/teact/teact';

import type { ApiTokenWithPrice } from '../../api/types';

import getChainNetworkIcon from '../../util/swap/getChainNetworkIcon';
import { getIsNativeToken } from '../../util/tokens';
import { ASSET_LOGO_PATHS } from './helpers/assetLogos';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Dropdown, { type DropdownItem } from './Dropdown';

import styles from './TokenDropdown.module.scss';

export type TokenWithId = Pick<ApiTokenWithPrice, 'slug' | 'symbol' | 'image' | 'chain'> & {
  /**
   * The token unique id to use instead of slug.
   * Made for cases when there multiple dropdown items with the same token.
   */
  id?: string;
};

interface OwnProps<T extends TokenWithId> {
  selectedToken?: T | string;
  allTokens?: T[];
  isMultichainAccount?: boolean;
  theme?: 'purple';
  isInMode?: boolean;
  isDisabled?: boolean;
  /** `id` is the token slug, unless an `id` property is specified explicitly in the `allTokens` items */
  onChange?: (id: string, token: T) => void;
}

const EMPTY_TOKEN_LIST: never[] = [];

function TokenDropdown<T extends TokenWithId>({
  selectedToken,
  allTokens = EMPTY_TOKEN_LIST,
  isMultichainAccount,
  theme,
  isInMode,
  isDisabled,
  onChange,
}: OwnProps<T>) {
  const lang = useLang();

  const buttonPrefixText = lang('$in_currency', { currency: '' });
  const buttonPrefix = useMemo(
    () => {
      return isInMode && (
        <span className={styles.prefix}>
          {buttonPrefixText}
        </span>
      );
    },
    [isInMode, buttonPrefixText],
  );

  const items = useMemo(
    () => allTokens.map((token) => tokenToDropdownItem(token, isMultichainAccount)),
    [allTokens, isMultichainAccount],
  );

  const tokenById = useMemo(
    () => allTokens.reduce<Record<string, T>>((byId, token) => {
      byId[getTokenId(token)] = token;
      return byId;
    }, {}),
    [allTokens],
  );

  const handleChange = useLastCallback((id: string) => {
    const token = tokenById[id];
    onChange?.(id, token);
  });

  if (!items.length) {
    return undefined;
  }

  const selectedTokenId = !selectedToken || typeof selectedToken === 'string'
    ? selectedToken
    : getTokenId(selectedToken);

  return (
    <Dropdown
      items={items}
      selectedValue={selectedTokenId}
      buttonPrefix={buttonPrefix}
      className={styles.dropdown}
      menuClassName={theme && styles[theme]}
      disabled={isDisabled}
      onChange={handleChange}
    />
  );
}

export default memo(TokenDropdown);

export function getTokenId(token: TokenWithId) {
  return token.id ?? token.slug;
}

export function tokenToDropdownItem(token: TokenWithId, isMultichainAccount?: boolean): DropdownItem {
  return {
    value: getTokenId(token),
    icon: ASSET_LOGO_PATHS[token.symbol.toLowerCase() as keyof typeof ASSET_LOGO_PATHS]
      || token.image,
    overlayIcon: isMultichainAccount && !getIsNativeToken(token.slug) ? getChainNetworkIcon(token.chain) : undefined,
    name: token.symbol,
  };
}
