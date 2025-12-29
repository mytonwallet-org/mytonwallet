import React, { memo, useMemo } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNft } from '../../../../api/types';

import { selectCurrentAccountState } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { getCountDaysToDate } from '../../../../util/dateFormat';
import { filterExpiringDomains, getDnsExpirationDate, getDomainsExpirationDate } from '../../../../util/dns';
import { stopEvent } from '../../../../util/domEvents';

import useCurrentOrPrev from '../../../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useForceUpdate from '../../../../hooks/useForceUpdate';
import useLang from '../../../../hooks/useLang';

import Collapsible from '../../../ui/Collapsible';

import styles from './Warnings.module.scss';

interface StateProps {
  orderedAddresses?: string[];
  byAddress?: Record<string, ApiNft>;
  dnsExpiration?: Record<string, number>;
}

// Store the addresses that the user ignores for the current session
let ignoredAddressForRenewal: string[] = [];

function RenewDomainWarning({ orderedAddresses, byAddress, dnsExpiration }: StateProps) {
  const { openDomainRenewalModal } = getActions();

  const lang = useLang();
  const { isLandscape } = useDeviceScreen();
  const forceUpdate = useForceUpdate();

  const nftForRenewal = useMemo(() => {
    return filterExpiringDomains(orderedAddresses ?? [], byAddress, dnsExpiration)
      .filter(({ address }) => !ignoredAddressForRenewal.includes(address));
    // eslint-disable-next-line react-hooks-static-deps/exhaustive-deps
  }, [byAddress, ignoredAddressForRenewal, orderedAddresses]);
  const isShown = nftForRenewal.length > 0;
  const renderedNftForRenewal = useCurrentOrPrev(isShown ? nftForRenewal : undefined, true);

  const expireInDays = useMemo(() => {
    const date = getDomainsExpirationDate(renderedNftForRenewal ?? [], undefined, dnsExpiration);

    return date ? getCountDaysToDate(date) : undefined;
  }, [renderedNftForRenewal, dnsExpiration]);

  const expiredDomains = useMemo(() => {
    if (!expireInDays || expireInDays >= 0 || !renderedNftForRenewal) return [];

    const now = Date.now();

    return renderedNftForRenewal.filter((nft) => {
      const date = getDnsExpirationDate(nft, dnsExpiration);
      return date && date < now;
    });
  }, [dnsExpiration, expireInDays, renderedNftForRenewal]);

  function handleClick() {
    const addresses = (renderedNftForRenewal ?? []).map(({ address }) => address);
    openDomainRenewalModal({ addresses });
  }

  function handleClose(e: React.MouseEvent) {
    stopEvent(e);

    ignoredAddressForRenewal = [
      ...ignoredAddressForRenewal,
      ...(nftForRenewal.map(({ address }) => address)),
    ];

    forceUpdate();
  }

  function renderPreview() {
    const previewNfts = (renderedNftForRenewal ?? []).slice(0, 3);
    return (
      <div className={styles.domainPreviewWrapper}>
        {previewNfts.map((nft, index) => {
          return (
            <img
              key={nft.address}
              src={nft.thumbnail}
              alt={nft.name}
              style={`--index: ${index}`}
              className={buildClassName(styles.domainPreview, styles[`domainPreview_${previewNfts.length}`])}
            />
          );
        })}
      </div>
    );
  }

  function renderWarningMessage() {
    if (expireInDays === undefined) return undefined;

    if (nftForRenewal.length === 1) {
      return expireInDays < 0
        ? lang('$domain_was_expired', { domain: nftForRenewal[0].name })
        : lang('$domain_expire', {
          domain: nftForRenewal[0].name,
          days: lang('$in_days', expireInDays, 'i'),
        });
    }

    return expireInDays < 0
      ? lang('$domains_was_expired', { domain: expiredDomains.length }, undefined, expiredDomains.length)
      : lang('$domains_expire', {
        domain: nftForRenewal.length,
        days: lang('$in_days', expireInDays, 'i'),
      }, undefined, nftForRenewal.length);
  }

  return (
    <Collapsible isShown={isShown}>
      <div
        className={buildClassName(
          styles.wrapper,
          styles.wrapperFlex,
          isLandscape && styles.wrapper_landscape,
        )}
        onClick={handleClick}
      >
        {renderPreview()}
        <div>
          {(renderedNftForRenewal ?? []).length === 1 ? lang('Renew Domain') : lang('Renew Domains')}
          <i className={buildClassName(styles.icon, 'icon-chevron-right')} aria-hidden />
          <p className={buildClassName(styles.text, styles.light)}>
            {renderWarningMessage()}
          </p>
        </div>
        <button type="button" className={styles.closeButton} aria-label={lang('Close')} onClick={handleClose}>
          <i className="icon-close" aria-hidden />
        </button>
      </div>
    </Collapsible>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { nfts } = selectCurrentAccountState(global) || {};

  return {
    orderedAddresses: nfts?.orderedAddresses,
    byAddress: nfts?.byAddress,
    dnsExpiration: nfts?.dnsExpiration,
  };
})(RenewDomainWarning));
