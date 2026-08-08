import React, { memo, useEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { ApiChain, ApiTokenDetails } from '../../api/types';
import type { IAnchorPosition, UserToken } from '../../global/types';
import type { DropdownItem } from '../ui/Dropdown';

import { selectTokenDetails } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { compact } from '../../util/iteratees';
import { openUrl } from '../../util/openUrl';
import { getExplorerTokenUrl, isValidUrl } from '../../util/url';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import DropdownMenu from '../ui/DropdownMenu';

import styles from './Header.module.scss';

interface OwnProps {
  token: UserToken;
  isScrolled?: boolean;
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  details?: ApiTokenDetails;
  tokenAddress?: string;
  isTestnet?: boolean;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
}

function Header({
  token,
  isScrolled,
  onBackClick,
  details,
  tokenAddress,
  isTestnet,
  selectedExplorerIds,
}: OwnProps & StateProps) {
  const lang = useLang();
  const menuButtonRef = useRef<HTMLButtonElement>();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();

  useHistoryBack({ isActive: true, onBack: onBackClick });

  useEffect(() => captureEscKeyListener(onBackClick), [onBackClick]);

  const explorerUrl = getExplorerTokenUrl(
    token.chain, token.cmcSlug, tokenAddress, isTestnet, selectedExplorerIds?.[token.chain],
  );

  // The links open a browser instead of dispatching an action, so they are keyed by their own URL
  const menuItems = useMemo(() => buildLinkItems(details, explorerUrl), [details, explorerUrl]);

  const handleSelect = useLastCallback((url: string) => {
    void openUrl(url);
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
    <div className={buildClassName(styles.root, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
      <Button className={styles.backButton} isSimple isText onClick={onBackClick}>
        <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />
        <span>{lang('Back')}</span>
      </Button>

      <h3 className={styles.title}>{token.name}</h3>

      {Boolean(menuItems.length) && (
        <Button
          ref={menuButtonRef}
          className={styles.menuButton}
          isSimple
          isText
          ariaLabel={lang('Actions')}
          onClick={openMenu}
        >
          <i className="icon-menu-dots" aria-hidden />
        </Button>
      )}

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

function buildLinkItems(details?: ApiTokenDetails, explorerUrl?: string): DropdownItem<string>[] {
  const { aggregatorLinks, docsUrl, sourceCodeUrl } = details ?? {};

  const groups: DropdownItem<string>[][] = [
    aggregatorLinks
      ?.filter(({ url }) => isValidUrl(url))
      .map(({ name, url }) => ({ name, value: url, noTranslate: true })) ?? [],
    compact([
      docsUrl && isValidUrl(docsUrl) && { name: 'Documentation', value: docsUrl },
      sourceCodeUrl && isValidUrl(sourceCodeUrl) && { name: 'Source Code', value: sourceCodeUrl },
    ]),
    compact([explorerUrl && { name: 'Open in Explorer', fontIcon: 'menu-globe', value: explorerUrl }]),
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
    };
  })(Header),
);
