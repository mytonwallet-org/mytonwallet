import React, { memo, useEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { ApiChain, ApiTokenDetails } from '../../api/types';
import type { IAnchorPosition, UserToken } from '../../global/types';
import type { DropdownItem } from '../ui/Dropdown';

import { selectTokenDetails } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import getTestId from '../../util/getTestId';
import { compact } from '../../util/iteratees';
import { openUrl } from '../../util/openUrl';
import { shareUrl } from '../../util/share';
import { getIsRwaStockToken, getTokenName } from '../../util/tokens';
import { getExplorerTokenUrl, getViewTokenUrl, isValidUrl } from '../../util/url';
import { IS_IOS, IS_TOUCH_ENV } from '../../util/windowEnvironment';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TokenLabel from '../common/TokenLabel';
import Button from '../ui/Button';
import DropdownMenu from '../ui/DropdownMenu';

import styles from './Header.module.scss';

interface OwnProps {
  token: UserToken;
  isScrolled?: boolean;
  className?: string;
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  details?: ApiTokenDetails;
  tokenAddress?: string;
  isTestnet?: boolean;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
  areTokenNamesLocalized?: boolean;
}

// `shareUrl` opens the OS share sheet on touch devices and copies the link elsewhere
const SHARE_ITEM: DropdownItem<string> = IS_TOUCH_ENV
  ? { name: 'Share', fontIcon: IS_IOS ? 'share-ios' : 'share-android', value: 'share' }
  : { name: 'Copy Link', fontIcon: 'menu-copy', value: 'share' };

function Header({
  token,
  isScrolled,
  className,
  onBackClick,
  details,
  tokenAddress,
  isTestnet,
  selectedExplorerIds,
  areTokenNamesLocalized,
}: OwnProps & StateProps) {
  const lang = useLang();
  const menuButtonRef = useRef<HTMLButtonElement>();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();

  useHistoryBack({ isActive: true, onBack: onBackClick });

  useEffect(() => captureEscKeyListener(onBackClick), [onBackClick]);

  const explorerUrl = getExplorerTokenUrl(
    token.chain, token.cmcSlug, tokenAddress, isTestnet, selectedExplorerIds?.[token.chain],
  );

  // Link items use their URL as the value. `share` is not a URL, so it never collides with a link.
  const menuItems = useMemo(() => buildMenuItems(details, explorerUrl), [details, explorerUrl]);

  const handleSelect = useLastCallback((value: string) => {
    if (value === SHARE_ITEM.value) {
      void shareUrl(getViewTokenUrl({ chain: token.chain, slug: token.slug, tokenAddress }, isTestnet));
      return;
    }

    void openUrl(value);
  });

  const openMenu = useLastCallback(() => {
    const { left, right, bottom: y } = menuButtonRef.current!.getBoundingClientRect();
    // RTL: mirror the anchor edge
    setMenuAnchor({ x: lang.isRtl ? left : right, y });
  });

  const closeMenu = useLastCallback(() => {
    setMenuAnchor(undefined);
  });

  return (
    <div className={buildClassName(styles.root, className, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
      <Button className={styles.backButton} isSimple isText onClick={onBackClick}>
        <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />
        <span>{lang('Back')}</span>
      </Button>

      <h3 className={styles.title}>
        <span className={styles.titleText}>{getTokenName(lang, token, areTokenNamesLocalized)}</span>
        {token.label && <TokenLabel label={token.label} isRwaStock={getIsRwaStockToken(token)} />}
      </h3>

      <Button
        ref={menuButtonRef}
        className={styles.menuButton}
        isSimple
        isText
        ariaLabel={lang('Actions')}
        testId={getTestId('token_more_button')}
        onClick={openMenu}
      >
        <i className="icon-menu-dots" aria-hidden />
      </Button>

      <DropdownMenu
        isOpen={Boolean(menuAnchor)}
        items={menuItems}
        menuAnchor={menuAnchor}
        menuPositionX="right"
        shouldTranslateOptions
        withPortal
        onSelect={handleSelect}
        onClose={closeMenu}
      />
    </div>
  );
}

function buildMenuItems(details?: ApiTokenDetails, explorerUrl?: string): DropdownItem<string>[] {
  const { aggregatorLinks, docsUrl, sourceCodeUrl } = details ?? {};

  const groups: DropdownItem<string>[][] = [
    aggregatorLinks
      ?.filter(({ url }) => isValidUrl(url))
      .map(({ name, url }) => ({ name, value: url, noTranslate: true })) ?? [],
    compact([
      docsUrl && isValidUrl(docsUrl) && { name: 'Documentation', value: docsUrl },
      sourceCodeUrl && isValidUrl(sourceCodeUrl) && { name: 'Source Code', value: sourceCodeUrl },
    ]),
    compact([explorerUrl && { name: 'Open in Explorer', fontIcon: 'menu-globe', value: explorerUrl }, SHARE_ITEM]),
  ];

  // `DropdownMenu` draws the delimiter above an item, so it goes on the first item of every group
  // except the topmost one
  return groups
    .filter((group) => group.length)
    .flatMap((group, index) => (index === 0
      ? group
      : [{ ...group[0], withDelimiter: true }, ...group.slice(1)]));
}

export default memo(
  withGlobal<OwnProps>((global, { token }): StateProps => {
    return {
      details: selectTokenDetails(global, token.slug)?.data,
      tokenAddress: global.tokenInfo.bySlug[token.slug]?.tokenAddress,
      isTestnet: global.settings.isTestnet,
      selectedExplorerIds: global.settings.selectedExplorerIds,
      areTokenNamesLocalized: global.settings.areTokenNamesLocalized,
    };
  })(Header),
);
