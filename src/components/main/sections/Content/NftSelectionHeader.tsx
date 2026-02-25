import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNft, ApiNftCollection } from '../../../../api/types';
import { type IAnchorPosition } from '../../../../global/types';

import { IS_CORE_WALLET } from '../../../../config';
import {
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import captureEscKeyListener from '../../../../util/captureEscKeyListener';
import { getCountDaysToDate } from '../../../../util/dateFormat';
import { getDomainsExpirationDate, isRenewableDnsNft } from '../../../../util/dns';
import { compact } from '../../../../util/iteratees';

import { getIsPortrait } from '../../../../hooks/useDeviceScreen';
import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import Button from '../../../ui/Button';
import { type DropdownItem } from '../../../ui/Dropdown';
import DropdownMenu from '../../../ui/DropdownMenu';

import styles from './NftCollectionHeader.module.scss';

type MenuHandler = 'send' | 'hide' | 'renew' | 'burn' | 'select-all';

interface StateProps {
  isViewMode: boolean;
  byAddress?: Record<string, ApiNft>;
  dnsExpiration?: Record<string, number>;
  selectedNfts?: ApiNft[];
  currentCollection?: ApiNftCollection;
}

function NftSelectionHeader({
  isViewMode, selectedNfts, byAddress, dnsExpiration, currentCollection,
}: StateProps) {
  const {
    selectAllNfts, clearNftsSelection, startTransfer, burnNfts, openHideNftModal, openDomainRenewalModal,
  } = getActions();

  const lang = useLang();
  const amount = selectedNfts?.length ?? 1;
  const isActive = Boolean(selectedNfts?.length);
  const areAllSelectedRenewableDns = useMemo(() => {
    return selectedNfts?.length
      ? selectedNfts.every((nft) => isRenewableDnsNft(byAddress?.[nft.address]))
      : false;
  }, [byAddress, selectedNfts]);
  const dnsExpireInDays = useMemo(() => {
    if (!areAllSelectedRenewableDns) return undefined;
    const date = getDomainsExpirationDate(selectedNfts ?? [], byAddress, dnsExpiration);

    return date ? getCountDaysToDate(date) : undefined;
  }, [areAllSelectedRenewableDns, dnsExpiration, selectedNfts, byAddress]);
  const tonDnsMultiSelected = (selectedNfts?.length ?? 0) > 1;

  useHistoryBack({
    isActive,
    onBack: clearNftsSelection,
  });

  useEffect(() => (isActive ? captureEscKeyListener(clearNftsSelection) : undefined), [isActive]);

  const menuItems: DropdownItem<MenuHandler>[] = useMemo(() => {
    return compact([
      !isViewMode && {
        name: 'Send',
        value: 'send',
      },
      !isViewMode && areAllSelectedRenewableDns && {
        name: tonDnsMultiSelected ? 'Renew All' : 'Renew',
        value: 'renew',
        description: dnsExpireInDays && dnsExpireInDays < 0
          ? (tonDnsMultiSelected ? '$expired_many' : 'Expired')
          : lang('$expires_in %days%', {
            days: lang('$in_days', dnsExpireInDays),
          }, undefined, selectedNfts?.length ?? 1) as string,
      } satisfies DropdownItem<MenuHandler>,
      !IS_CORE_WALLET && {
        name: 'Hide',
        value: 'hide',
      } satisfies DropdownItem<MenuHandler>,
      !isViewMode && {
        name: 'Burn',
        value: 'burn',
        isDangerous: true,
      } satisfies DropdownItem<MenuHandler>, {
        name: 'Select All',
        value: 'select-all',
        withDelimiter: true,
      },
    ]);
  }, [areAllSelectedRenewableDns, dnsExpireInDays, isViewMode, lang, selectedNfts?.length, tonDnsMultiSelected]);

  const handleSendClick = useLastCallback(() => {
    const nfts = selectedNfts!.map((nft) => byAddress![nft.address]) ?? [];

    clearNftsSelection();

    startTransfer({
      isPortrait: getIsPortrait(),
      nfts,
    });
  });

  const handleBurnClick = useLastCallback(() => {
    const nfts = selectedNfts!.map((nft) => byAddress![nft.address]) ?? [];

    clearNftsSelection();

    burnNfts({ nfts });
  });

  const handleHideClick = useLastCallback(() => {
    clearNftsSelection();

    openHideNftModal({ addresses: selectedNfts!.map((e) => e.address), isCollection: false });
  });

  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();
  const isMenuOpen = Boolean(menuAnchor);
  const ref = useRef<HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();
  const handleMenuOpen = useLastCallback(() => {
    const { right: x, bottom: y } = ref.current!.getBoundingClientRect();
    setMenuAnchor({ x, y });
  });
  const handleMenuClose = useLastCallback(() => {
    setMenuAnchor(undefined);
  });
  const getTriggerElement = useLastCallback(() => ref.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback(() => ({ withPortal: true }));

  const handleMenuItemClick = useLastCallback((value: MenuHandler) => {
    switch (value) {
      case 'send': {
        handleSendClick();
        break;
      }
      case 'hide': {
        handleHideClick();
        break;
      }
      case 'burn': {
        handleBurnClick();
        break;
      }
      case 'select-all': {
        selectAllNfts({ collectionAddress: currentCollection?.address });
        break;
      }
      case 'renew': {
        openDomainRenewalModal({ addresses: selectedNfts!.map((e) => e.address) });
        break;
      }
    }
  });

  return (
    <div className={styles.root}>
      <Button
        isSimple
        isText
        ariaLabel={lang('Back')}
        className={styles.backButton}
        onClick={clearNftsSelection}
      >
        <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />
      </Button>
      <div className={styles.content}>
        <div className={styles.title}>
          {amount > 1 ? lang('%amount% NFTs Selected', { amount }) : lang('1 NFT Selected')}
        </div>
      </div>
      <div>
        <Button isSimple ref={ref} className={styles.menuButton} onClick={handleMenuOpen} ariaLabel={lang('Open Menu')}>
          <i className="icon-menu-dots" aria-hidden />
        </Button>
        <DropdownMenu
          isOpen={isMenuOpen}
          ref={menuRef}
          withPortal
          shouldTranslateOptions
          menuPositionX="right"
          menuAnchor={menuAnchor}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
          buttonClassName={styles.menuItem}
          bubbleClassName={styles.menu}
          itemDescriptionClassName={styles.menuItemDescription}
          items={menuItems}
          onSelect={handleMenuItemClick}
          onClose={handleMenuClose}
        />
      </div>
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const {
    selectedNfts, byAddress, currentCollection, dnsExpiration,
  } = selectCurrentAccountState(global)?.nfts || {};

  return {
    selectedNfts,
    byAddress,
    currentCollection,
    dnsExpiration,
    isViewMode: selectIsCurrentAccountViewMode(global),
  };
})(NftSelectionHeader));
