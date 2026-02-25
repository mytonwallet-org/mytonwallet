import React, { memo, useMemo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import { SettingsState } from '../../global/types';

import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getDappConnectionUniqueId } from '../../util/getDappConnectionUniqueId';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';

import useHorizontalScroll from '../../hooks/useHorizontalScroll';
import useLang from '../../hooks/useLang';

import DappFeedItem from './DappFeedItem';

import styles from './DappFeed.module.scss';
import exploreStyles from './Explore.module.scss';

interface StateProps {
  dapps: StoredDappConnection[];
  dappLastOpenedDatesByUrl?: Record<string, number>;
}

type DappWithLastOpenedDate = StoredDappConnection & { lastOpenedAt?: number };

const MAX_DAPPS_FOR_PILL_MODE = 3;
const HIDDEN_FROM_FEED_DAPP_URLS = new Set(['https://checkin.mytonwallet.org']);

function DappFeed({ dapps: dappsFromState, dappLastOpenedDatesByUrl }: StateProps) {
  const { openSettingsWithState, closeExplore } = getActions();

  const lang = useLang();

  const containerRef = useRef<HTMLDivElement>();
  const dapps: DappWithLastOpenedDate[] = useMemo(() => {
    const sortedDapps = dappsFromState
      .slice()
      .filter((dapp) => !HIDDEN_FROM_FEED_DAPP_URLS.has(dapp.url))
      .map((dapp) => ({ ...dapp, lastOpenedAt: dappLastOpenedDatesByUrl?.[dapp.url] }))
      .sort(compareDapps);

    // Remove duplicates, since we now support multiple connections per dapp. Keep the most recent connection.
    const seen = new Set<string>();
    return sortedDapps.filter(({ url }) => {
      if (seen.has(url)) return false;
      seen.add(url);
      return true;
    });
  }, [dappLastOpenedDatesByUrl, dappsFromState]);

  const mode = dapps.length > MAX_DAPPS_FOR_PILL_MODE ? 'tile' : 'pill';
  const isPillMode = mode === 'pill';
  const iconWrapperClassName = isPillMode ? styles.iconPill : styles.iconTile;
  const fullClassName = buildClassName(
    styles.feed,
    isPillMode ? styles.pills : styles.tiles,
    !dapps.length && styles.feedEmpty,
    'dapps-feed',
  );

  function openSettings() {
    closeExplore(undefined, { forceOnHeavyAnimation: true });
    openSettingsWithState({ state: SettingsState.Dapps }, { forceOnHeavyAnimation: true });
  }

  useHorizontalScroll({
    containerRef,
    isDisabled: IS_TOUCH_ENV || dapps.length === 0,
    shouldPreventDefault: true,
    contentSelector: '.dapps-feed',
  });

  if (!dapps.length) {
    return undefined;
  }

  return (
    <div className={styles.root} ref={containerRef}>
      <h2 className={exploreStyles.sectionHeader}>{lang('Connected Apps')}</h2>

      <div className={fullClassName}>
        {dapps?.map((dapp) => renderDapp(dapp, mode))}

        {!!dapps.length && (
          <div
            className={styles.settingsButton}
            role="button"
            tabIndex={0}
            title={isPillMode ? lang('Settings') : undefined}
            aria-label={isPillMode ? lang('Settings') : undefined}
            onClick={openSettings}
          >
            <div className={buildClassName(styles.settingsIconContainer, iconWrapperClassName)}>
              <i className="icon-params" aria-hidden />
            </div>
            {!isPillMode && <span className={styles.settingsLabel}>{lang('Settings')}</span>}
          </div>
        )}
      </div>
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { dapps = MEMO_EMPTY_ARRAY } = selectCurrentAccountState(global) || {};
  const { dappLastOpenedDatesByUrl } = selectCurrentAccountState(global) || {};

  return { dapps, dappLastOpenedDatesByUrl };
})(DappFeed));

function compareDapps(a: DappWithLastOpenedDate, b: DappWithLastOpenedDate) {
  const aLastOpened = a.lastOpenedAt || 0;
  const bLastOpened = b.lastOpenedAt || 0;

  if (aLastOpened !== bLastOpened) {
    return bLastOpened - aLastOpened;
  }

  return b.connectedAt - a.connectedAt;
}

function renderDapp(dapp: DappWithLastOpenedDate, mode: 'pill' | 'tile') {
  const {
    iconUrl, name, url,
  } = dapp;

  const key = `dapp-${url}-${getDappConnectionUniqueId(dapp)}`;

  return (
    <DappFeedItem
      key={key}
      iconUrl={iconUrl}
      name={name}
      url={url}
      mode={mode}
      isExternal={!!dapp.sse}
    />
  );
}
