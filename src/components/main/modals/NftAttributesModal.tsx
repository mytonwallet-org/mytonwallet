import React, { memo, useEffect, useMemo, useRef, useState } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiNft, ApiNftAttribute } from '../../../api/types';
import {
  type Account,
  type IAnchorPosition,
  MediaType,
  type SavedAddress,
  type Theme,
} from '../../../global/types';

import { IS_EXPLORER } from '../../../config';
import { selectCurrentAccountId, selectCurrentAccountState, selectNetworkAccounts } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { getChainTitle } from '../../../util/chain';
import { getCountDaysToDate } from '../../../util/dateFormat';
import { getDnsExpirationDate } from '../../../util/dns';
import { stopEvent } from '../../../util/domEvents';
import { getLocalAddressName } from '../../../util/getLocalAddressName';
import { disableSwipeToClose, enableSwipeToClose } from '../../../util/modalSwipeManager';
import { IS_ELECTRON, IS_MAC_OS } from '../../../util/windowEnvironment';

import useAppTheme from '../../../hooks/useAppTheme';
import useCurrentOrPrev from '../../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../../hooks/useDeviceScreen';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useSyncEffect from '../../../hooks/useSyncEffect';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import InteractiveTextField from '../../ui/InteractiveTextField';
import Modal from '../../ui/Modal';
import NftMenu from '../sections/Content/NftMenu';

import styles from './NftAttributesModal.module.scss';

import noImageSrcDark from '../../../assets/nftNoImageDark.svg';
import noImageSrcLight from '../../../assets/nftNoImageLight.svg';

interface StateProps {
  nft?: ApiNft;
  theme: Theme;
  dnsExpiration?: Record<string, number>;
  shouldShowOwnerInNftAttributes?: true;
  accounts?: Record<string, Account>;
  currentAccountId: string;
  savedAddresses?: SavedAddress[];
}

const FOLD_LIMIT = 5;
const ANIMATED_ICON_SIZE = 250; // Preview size (500px) / 2

function NftAttributesModal({
  nft,
  theme,
  dnsExpiration,
  accounts,
  currentAccountId,
  savedAddresses,
  shouldShowOwnerInNftAttributes,
}: StateProps) {
  const { closeNftAttributesModal, openMediaViewer, openNftCollection } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const menuButtonRef = useRef<HTMLButtonElement>();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();
  const { isPortrait } = useDeviceScreen();

  const isOpen = !!nft;
  const renderedNft = useCurrentOrPrev(nft, true);
  const renderedWithNftOwner = useCurrentOrPrev(shouldShowOwnerInNftAttributes || IS_EXPLORER, true);
  const {
    chain,
    ownerAddress,
    isScam,
    thumbnail,
    metadata: { lottie, attributes },
  } = renderedNft || { metadata: {} };
  const [hasImage, setHasImage] = useState<boolean>(Boolean(thumbnail));
  const attributesCount = attributes?.length || 0;
  const [isFolded, setIsFolded] = useState(attributesCount > FOLD_LIMIT);
  const tonDnsExpiration = getDnsExpirationDate(renderedNft, dnsExpiration);
  const dnsExpireInDays = tonDnsExpiration ? getCountDaysToDate(tonDnsExpiration) : undefined;
  const list = attributes?.slice(0, isFolded ? FOLD_LIMIT : undefined) || [];
  const isNoData = !renderedWithNftOwner && !renderedNft?.description && list.length === 0;

  useEffect(() => {
    setHasImage(Boolean(thumbnail));
  }, [thumbnail]);

  const ownerAddressName = useMemo(() => {
    if (!renderedWithNftOwner || !chain || !ownerAddress) return undefined;

    return getLocalAddressName({
      address: ownerAddress,
      chain,
      currentAccountId,
      accounts,
      savedAddresses,
    });
  }, [accounts, chain, currentAccountId, ownerAddress, savedAddresses, renderedWithNftOwner]);

  useSyncEffect(() => {
    setIsFolded(attributesCount > FOLD_LIMIT + 1);
  }, [attributesCount, nft]);

  useEffect(() => {
    if (!isOpen) return undefined;

    disableSwipeToClose();

    return enableSwipeToClose;
  }, [isOpen]);

  function handleImageLoadError() {
    setHasImage(false);
  }

  const handleOpenMenu = useLastCallback(() => {
    const { right: x, y } = menuButtonRef.current!.getBoundingClientRect();
    setMenuAnchor({ x, y });
  });

  const handleCloseMenu = useLastCallback(() => {
    setMenuAnchor(undefined);
  });

  const handleExpand = useLastCallback((e: React.MouseEvent<HTMLAnchorElement>) => {
    stopEvent(e);

    setIsFolded(false);
  });

  const handleNftClick = useLastCallback(() => {
    openMediaViewer({ mediaId: renderedNft!.address, mediaType: MediaType.Nft });
  });

  const handleCollectionClick = useLastCallback((e: React.MouseEvent<HTMLDivElement>) => {
    stopEvent(e);

    closeNftAttributesModal(undefined, { forceOnHeavyAnimation: true });
    openNftCollection({
      chain: renderedNft!.chain,
      address: renderedNft!.collectionAddress!,
    }, { forceOnHeavyAnimation: true });
  });

  const renderAttributeRow = (attribute: ApiNftAttribute, index: number) => {
    const isFirst = index === 0;
    const isLast = index === list.length - 1;

    return (
      <tr key={index}>
        <th className={buildClassName(styles.attributeName, isFirst && styles.first, isLast && styles.last)}>
          {attribute.trait_type}
        </th>
        <td className={buildClassName(styles.attributeValue, isFirst && styles.first, isLast && styles.last)}>
          {attribute.value}
        </td>
      </tr>
    );
  };

  if (!renderedNft) return undefined;

  return (
    <Modal
      isOpen={isOpen}
      className={styles.modal}
      dialogClassName={styles.dialog}
      contentClassName={styles.container}
      onClose={closeNftAttributesModal}
    >
      <button
        type="button"
        aria-label={lang('Close')}
        className={styles.closeButton}
        onClick={() => closeNftAttributesModal()}
      >
        <i
          className={buildClassName(
            styles.icon,
            styles.actionIcon,
            isPortrait && !(IS_ELECTRON && IS_MAC_OS) ? 'icon-chevron-left' : 'icon-close',
          )}
          aria-hidden
        />
      </button>
      <NftMenu
        nft={renderedNft}
        ref={menuButtonRef}
        dnsExpireInDays={dnsExpireInDays}
        menuAnchor={menuAnchor}
        className={styles.menuButton}
        onOpen={handleOpenMenu}
        onClose={handleCloseMenu}
      />
      <div
        className={buildClassName(styles.nftInfo, 'nft-container')}
        data-nft-address={renderedNft.address}
      >
        {!hasImage && !lottie ? (
          <div className={buildClassName(styles.noImageWrapper, 'rounded-font')}>
            <img src={appTheme === 'dark' ? noImageSrcDark : noImageSrcLight} alt="" className={styles.noImage} />
            <span className={styles.noImageText}>{lang('No Image')}</span>
          </div>
        ) : lottie ? (
          <AnimatedIconWithPreview
            size={ANIMATED_ICON_SIZE}
            shouldStretch
            play={isOpen}
            noLoop={false}
            tgsUrl={lottie}
            previewUrl={renderedNft.thumbnail}
            className={styles.thumbnail}
            noPreviewTransition
            onClick={handleNftClick}
          />
        ) : (
          <>
            <img
              src={renderedNft.thumbnail}
              alt={lang('Preview')}
              role="button"
              tabIndex={0}
              className={styles.thumbnail}
              onError={handleImageLoadError}
              onClick={handleNftClick}
            />
            {Boolean(renderedNft.image) && (
              <img
                src={renderedNft.image}
                alt=""
                role="button"
                tabIndex={0}
                className={styles.fullImage}
                onClick={handleNftClick}
              />
            )}
          </>
        )}
        <div className={styles.info}>
          <div className={styles.nftName}>{renderedNft.name}</div>
          {renderedNft.collectionName && (
            <div className={styles.collectionName} onClick={handleCollectionClick} tabIndex={0} role="button">
              {renderedNft.collectionName}
              <i className={buildClassName(styles.collectionNameIcon, 'icon-chevron-right')} aria-hidden />
            </div>
          )}
        </div>
      </div>

      <div className={buildClassName(styles.content, isNoData && styles.noData)}>
        {renderedWithNftOwner && (
          <>
            <h3 className={styles.label}>{lang('Owner')}</h3>
            <InteractiveTextField
              chain={chain}
              addressName={ownerAddressName}
              address={ownerAddress}
              copyNotification={lang('%chain% Address Copied', { chain: chain ? getChainTitle(chain) : '' }) as string}
              className={styles.copyButtonWrapper}
              textClassName={isScam ? styles.scamAddress : undefined}
            />
          </>
        )}

        {isNoData && lang('No additional data.')}

        {renderedNft.description && (
          <>
            <h3 className={styles.label}>{lang('Description')}</h3>
            <div className={styles.description}>
              {renderedNft.description}
            </div>
          </>
        )}

        {list.length > 0 && (
          <>
            <h3 className={styles.label}>{lang('Attributes')}</h3>
            <table className={styles.attributesList}>
              <tbody>
                {list.map(renderAttributeRow)}
              </tbody>
            </table>

            {isFolded && (
              <a href="#" className={styles.expandButton} onClick={handleExpand}>
                {lang('Show All')}
                <i className={buildClassName(styles.expandButtonIcon, 'icon-chevron-down')} aria-hidden />
              </a>
            )}
          </>
        )}
      </div>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const currentAccountId = selectCurrentAccountId(global)!;
  const accountState = selectCurrentAccountState(global);
  const accounts = selectNetworkAccounts(global);

  const { currentNftForAttributes, shouldShowOwnerInNftAttributes, nfts, savedAddresses } = accountState || {};
  const { dnsExpiration } = nfts || {};

  return {
    currentAccountId,
    nft: currentNftForAttributes,
    theme: global.settings.theme,
    dnsExpiration,
    accounts,
    savedAddresses,
    shouldShowOwnerInNftAttributes,
  };
})(NftAttributesModal));
