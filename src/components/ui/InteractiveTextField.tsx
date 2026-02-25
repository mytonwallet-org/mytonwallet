import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';
import type { IAnchorPosition, SavedAddress } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from './Dropdown';

import { closeAllOverlays } from '../../global/helpers/misc';
import {
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectIsMultichainAccount,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { getChainTitle } from '../../util/chain';
import { copyTextToClipboard } from '../../util/clipboard';
import { stopEvent } from '../../util/domEvents';
import { openUrl } from '../../util/openUrl';
import { shareUrl } from '../../util/share';
import { MEANINGFUL_CHAR_LENGTH, shortenAddress } from '../../util/shortenAddress';
import { getExplorerAddressUrl, getExplorerName, getHostnameFromUrl, getViewTransactionUrl } from '../../util/url';
import { IS_IOS, IS_TOUCH_ENV, REM } from '../../util/windowEnvironment';
import windowSize from '../../util/windowSize';

import useFlag from '../../hooks/useFlag';
import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useLongPress from '../../hooks/useLongPress';

import DeleteSavedAddressModal from '../main/modals/DeleteSavedAddressModal';
import Button from './Button';
import DropdownMenu from './DropdownMenu';
import Input from './Input';
import MenuBackdrop from './MenuBackdrop';
import Modal from './Modal';
import Transition from './Transition';
import WalletAvatar from './WalletAvatar';

import styles from './InteractiveTextField.module.scss';
import modalStyles from './Modal.module.scss';

import scamImg from '../../assets/scam.svg';

interface OwnProps {
  chain?: ApiChain;
  address?: string;
  addressName?: string;
  addressUrl?: string;
  forceFullAddress?: boolean;
  isScam?: boolean;
  isTransaction?: boolean;
  text?: string;
  spoiler?: string;
  spoilerRevealText?: string;
  spoilerCallback?: NoneToVoidFunction;
  copyNotification?: string;
  className?: string;
  textClassName?: string;
  noDimming?: boolean;
  noSavedAddress?: boolean;
  noExplorer?: boolean;
  withShareInMenu?: boolean;
}

interface StateProps {
  savedAddresses?: SavedAddress[];
  isMultichainAccount?: boolean;
  isTestnet?: boolean;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
}

type MenuHandler = 'copy' | 'share' | 'addressBook' | 'explorer' | 'viewInApp';

const SAVED_ADDRESS_NAME_MAX_LENGTH = 255;
const MENU_VERTICAL_OFFSET_PX = -16;
const MENU_ITEM_HEIGHT_PX = 3 * REM;
const COMFORT_MARGIN_PX = REM;

function InteractiveTextField({
  chain,
  address,
  addressName,
  addressUrl,
  forceFullAddress = false,
  isScam,
  isTransaction,
  text = '',
  spoiler,
  spoilerRevealText,
  spoilerCallback,
  copyNotification,
  noSavedAddress,
  noExplorer,
  className,
  textClassName,
  savedAddresses,
  isTestnet,
  isMultichainAccount,
  noDimming,
  withShareInMenu,
  selectedExplorerIds,
}: OwnProps & StateProps) {
  const { showToast, addSavedAddress, openTemporaryViewAccount } = getActions();

  const addressNameRef = useRef<HTMLInputElement>();
  const contentRef = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const lang = useLang();
  const [isSaveAddressModalOpen, openSaveAddressModal, closeSaveAddressModal] = useFlag();
  const [isDeleteSavedAddressModalOpen, openDeletedSavedAddressModal, closeDeleteSavedAddressModal] = useFlag();
  const [savedAddressName, setSavedAddressName] = useState<string | undefined>(addressName);
  const [isConcealedWithSpoiler, , revealSpoiler] = useFlag(Boolean(spoiler));
  const isAddressAlreadySaved = useMemo(() => {
    return Boolean(address && chain && (savedAddresses || []).find((savedAddress) => {
      return savedAddress.address === address && savedAddress.chain === chain;
    }));
  }, [address, chain, savedAddresses]);

  const selectedExplorerId = chain ? selectedExplorerIds?.[chain] : undefined;
  const resolvedAddressUrl = addressUrl ?? (chain
    ? getExplorerAddressUrl(chain, address, isTestnet, selectedExplorerId)
    : undefined);
  const saveAddressTitle = lang(isAddressAlreadySaved ? 'Remove from Saved' : 'Save Address');
  const explorerTitle = lang('View on Explorer');
  const withSavedAddresses = Boolean(!isScam && !noSavedAddress && address);
  const withExplorer = Boolean(!noExplorer && resolvedAddressUrl);
  const isAddressCanBeViewed = Boolean(withSavedAddresses && !isAddressAlreadySaved);

  useEffect(() => {
    if (isSaveAddressModalOpen) {
      setSavedAddressName('');
    }
  }, [isSaveAddressModalOpen]);

  const handleSaveAddressSubmit = useLastCallback(() => {
    if (!savedAddressName || !address || !chain) {
      return;
    }

    addSavedAddress({ address, chain, name: savedAddressName });
    showToast({ message: lang('Address Saved'), icon: 'icon-star' });
    closeSaveAddressModal();
  });

  useEffect(() => (
    isSaveAddressModalOpen
      ? captureKeyboardListeners({ onEnter: handleSaveAddressSubmit })
      : undefined
  ), [handleSaveAddressSubmit, isSaveAddressModalOpen]);

  useFocusAfterAnimation(addressNameRef, !isSaveAddressModalOpen);

  const handleCopy = useLastCallback(() => {
    if (!copyNotification) return;
    showToast({ message: copyNotification, icon: 'icon-copy' });
    void copyTextToClipboard(address || text);
  });

  const handleShareTransaction = useLastCallback(() => {
    const url = getViewTransactionUrl(chain!, address!, isTestnet);

    void shareUrl(url);
  });

  const handleExplorerOpen = useLastCallback(() => {
    if (!chain) return;

    void openUrl(resolvedAddressUrl!, {
      title: getExplorerName(chain, selectedExplorerId),
      subtitle: getHostnameFromUrl(resolvedAddressUrl!),
      shouldSkipOverlayClose: true,
    });
  });

  const handleViewInApp = useLastCallback(async () => {
    if (!address || !chain) return;
    await closeAllOverlays();
    openTemporaryViewAccount({
      addressByChain: {
        [chain]: address,
      },
    });
  });

  const {
    isActionsMenuOpen,
    menuAnchor,
    menuPositionY,
    menuItems,
    handleMenuShow,
    handleMenuItemSelect,
    closeActionsMenu,
  } = useDropdownMenu({
    copy: handleCopy,
    share: handleShareTransaction,
    addressBook: isAddressAlreadySaved ? openDeletedSavedAddressModal : openSaveAddressModal,
    explorer: handleExplorerOpen,
    viewInApp: handleViewInApp,
  }, {
    isAddressAlreadySaved,
    isAddressCanBeViewed,
    isTransaction,
    withSavedAddresses,
    withExplorer,
    withShare: withShareInMenu,
    address,
    addressName,
  });

  const shouldUseMenu = !spoiler && IS_TOUCH_ENV && menuItems.length > 1;
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({ withPortal: true, preferredPositionY: menuPositionY }));

  const longPressHandlers = useLongPress({
    onClick: handleMenuShow,
    onStart: (_target: HTMLElement) => handleCopy(),
  });

  const handleRevealSpoiler = useLastCallback(() => {
    revealSpoiler();
    spoilerCallback?.();
  });

  function renderContentOrSpoiler() {
    const content = addressName || address || text;

    if (!spoiler) {
      return renderContent(content);
    }

    const isConcealed = isConcealedWithSpoiler || !content;
    return (
      <Transition activeKey={isConcealed ? 1 : 0} name="fade" className={styles.commentContainer}>
        {isConcealed ? (
          <span className={buildClassName(styles.button, styles.button_spoiler, textClassName)}>
            <i>{spoiler}</i>{' '}
            <span
              onClick={handleRevealSpoiler}
              tabIndex={0}
              role="button"
              className={styles.revealSpoiler}
            >
              {spoilerRevealText}
            </span>
          </span>
        ) : renderContent(content)}
      </Transition>
    );
  }

  function renderContent(content: string) {
    let renderedContent: string | TeactNode = content;
    if (!noDimming && !isTransaction && content === address && content.length > MEANINGFUL_CHAR_LENGTH * 2) {
      const prefix = content.substring(0, MEANINGFUL_CHAR_LENGTH);
      const suffixStart = content.length - MEANINGFUL_CHAR_LENGTH;
      const middle = content.substring(MEANINGFUL_CHAR_LENGTH, suffixStart);
      const suffix = content.substring(suffixStart);

      renderedContent = (
        <>
          <span className={styles.meaningfulPart}>{prefix}</span>
          <span className={styles.dimmedPart}>{middle}</span>
          <span className={styles.meaningfulPart}>{suffix}</span>
        </>
      );
    } else if (!noDimming && isTransaction) {
      renderedContent = <span className={styles.dimmedPart}>{content}</span>;
    }

    return (
      <span
        className={buildClassName(styles.button, isScam && styles.scam, textClassName)}
        tabIndex={0}
        role="button"
        title={!shouldUseMenu ? lang('Copy') : undefined}
        onClick={!shouldUseMenu ? handleCopy : undefined}
      >
        {isScam && <img src={scamImg} alt={lang('Scam')} className={styles.scamImage} />}
        {isMultichainAccount && !isTransaction && (
          <i
            className={buildClassName(styles.chainIcon, `icon-chain-${chain}`)}
            aria-label={chain && getChainTitle(chain)}
          />
        )}
        {renderedContent}
        {Boolean(addressName) && (
          <span className={buildClassName(styles.shortAddress, isScam && styles.scam)}>
            {forceFullAddress ? address : shortenAddress(address!)}
          </span>
        )}
        {Boolean(copyNotification) && !shouldUseMenu && (
          <i className={buildClassName(styles.icon, 'icon-copy')} aria-hidden />
        )}
      </span>
    );
  }

  function renderActions() {
    if (shouldUseMenu) {
      const iconClassName = buildClassName(
        styles.icon,
        styles.iconCaretDown,
        'icon-caret-down',
        isScam && styles.scam,
      );

      return (
        <>
          <i className={iconClassName} aria-hidden />
          <DropdownMenu
            ref={menuRef}
            withPortal
            shouldTranslateOptions
            isOpen={isActionsMenuOpen}
            items={menuItems}
            menuPositionY={menuPositionY}
            menuAnchor={menuAnchor}
            getLayout={getLayout}
            getMenuElement={getMenuElement}
            getRootElement={getRootElement}
            bubbleClassName={styles.menu}
            buttonClassName={styles.menuItem}
            fontIconClassName={styles.menuIcon}
            onSelect={handleMenuItemSelect}
            onClose={closeActionsMenu}
          />
        </>
      );
    }

    return (
      <>
        {withSavedAddresses && (
          <span
            className={styles.button}
            title={saveAddressTitle}
            aria-label={saveAddressTitle}
            tabIndex={0}
            role="button"
            onClick={isAddressAlreadySaved ? openDeletedSavedAddressModal : openSaveAddressModal}
          >
            <i
              className={buildClassName(
                styles.icon,
                styles.iconStar,
                isAddressAlreadySaved ? 'icon-star-filled' : 'icon-star',
              )}
              aria-hidden
            />
          </span>
        )}

        {isTransaction && (
          <span
            className={styles.button}
            title={lang('Share Link')}
            aria-label={lang('Share Link')}
            onClick={handleShareTransaction}
          >
            <i className={buildClassName(styles.icon, styles.iconShare, 'icon-link')} aria-hidden />
          </span>
        )}
        {isAddressCanBeViewed && (
          <span
            className={styles.button}
            title={lang('View in App')}
            aria-label={lang('View in App')}
            tabIndex={0}
            role="button"
            onClick={handleViewInApp}
          >
            <i className={buildClassName(styles.icon, 'icon-eye-outlined')} aria-hidden />
          </span>
        )}
        {withExplorer && (
          <span
            className={styles.button}
            title={explorerTitle}
            aria-label={explorerTitle}
            tabIndex={0}
            role="button"
            onClick={handleExplorerOpen}
          >
            <i className={buildClassName(styles.icon, 'icon-tonexplorer-small')} aria-hidden />
          </span>
        )}
      </>
    );
  }

  function renderSaveAddressModal() {
    return (
      <Modal
        title={lang('Save Address')}
        isCompact
        isOpen={isSaveAddressModalOpen}
        onClose={closeSaveAddressModal}
      >
        <p>{lang('You can save this address for quick access while sending.')}</p>
        <Input
          ref={addressNameRef}
          placeholder={lang('Name')}
          onInput={setSavedAddressName}
          value={savedAddressName}
          maxLength={SAVED_ADDRESS_NAME_MAX_LENGTH}
          className={styles.nameInput}
        />

        <div className={modalStyles.buttons}>
          <Button onClick={closeSaveAddressModal} className={modalStyles.button}>{lang('Cancel')}</Button>
          <Button
            onClick={handleSaveAddressSubmit}
            isPrimary
            isDisabled={!savedAddressName}
            className={modalStyles.button}
          >
            {lang('Save')}
          </Button>
        </div>
      </Modal>
    );
  }

  return (
    <>
      <MenuBackdrop
        isMenuOpen={isActionsMenuOpen && shouldUseMenu}
        contentRef={contentRef}
      />
      <div
        ref={contentRef}
        className={buildClassName(styles.wrapper, className)}
        {...(shouldUseMenu && !isActionsMenuOpen && {
          ...longPressHandlers,
          tabIndex: 0,
          role: 'button',
        })}
        onContextMenu={shouldUseMenu ? stopEvent : undefined}
      >
        {renderContentOrSpoiler()}
        {renderActions()}
      </div>

      {address && (
        <>
          {renderSaveAddressModal()}
          <DeleteSavedAddressModal
            isOpen={isDeleteSavedAddressModalOpen}
            address={address}
            chain={chain}
            onClose={closeDeleteSavedAddressModal}
          />
        </>
      )}
    </>
  );
}

export default memo(withGlobal<OwnProps>(
  (global): StateProps => {
    const accountId = selectCurrentAccountId(global);
    const accountState = selectCurrentAccountState(global);

    return {
      savedAddresses: accountState?.savedAddresses,
      isMultichainAccount: accountId ? selectIsMultichainAccount(global, accountId) : false,
      isTestnet: global.settings.isTestnet,
      selectedExplorerIds: global.settings.selectedExplorerIds,
    };
  },
)(InteractiveTextField));

function useDropdownMenu(
  menuHandlers: Record<MenuHandler, NoneToVoidFunction>,
  options: {
    withSavedAddresses?: boolean;
    withExplorer?: boolean;
    isAddressAlreadySaved?: boolean;
    isAddressCanBeViewed?: boolean;
    isTransaction?: boolean;
    withShare?: boolean;
    address?: string;
    addressName?: string;
  },
) {
  const [menuPositionY, setMenuPositionY] = useState<'top' | 'bottom'>('top');
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition | undefined>();
  const closeActionsMenu = useLastCallback(() => setMenuAnchor(undefined));
  const isActionsMenuOpen = Boolean(menuAnchor);

  const menuItems = useMemo<DropdownItem<MenuHandler>[]>(() => {
    const {
      isAddressAlreadySaved, isAddressCanBeViewed, isTransaction, withSavedAddresses, withExplorer, withShare,
      address, addressName,
    } = options;

    const items: DropdownItem<MenuHandler>[] = [{
      name: withSavedAddresses || isAddressCanBeViewed
        ? 'Copy Address'
        : (isTransaction ? 'Copy Transaction ID' : 'Copy'),
      fontIcon: 'copy',
      value: 'copy',
    }];

    if (isAddressCanBeViewed) {
      const shortAddress = shortenAddress(address!);
      items.unshift({
        name: addressName || shortAddress!,
        description: addressName ? shortAddress : undefined,
        icon: <WalletAvatar title={addressName || shortAddress} className={styles.menuAvatar} />,
        fontIcon: 'chevron-right',
        fontIconClassName: styles.menuIconChevronRight,
        value: 'viewInApp',
        withDelimiterAfter: true,
      });
    }

    if (withSavedAddresses) {
      items.push({
        name: isAddressAlreadySaved ? 'Remove from Saved' : 'Save Address',
        fontIcon: isAddressAlreadySaved ? 'star-filled' : 'star',
        value: 'addressBook',
      });
    }

    if (isTransaction || withShare) {
      items.push({
        name: 'Share Link',
        fontIcon: IS_IOS ? 'share-ios' : 'share-android',
        value: 'share',
      });
    }

    if (withExplorer) {
      items.push({
        name: 'View on Explorer',
        fontIcon: 'tonexplorer',
        value: 'explorer',
      });
    }

    return items;
  }, [options]);

  const handleMenuItemSelect = useLastCallback((value: MenuHandler) => {
    menuHandlers[value]?.();
    closeActionsMenu();
  });

  const handleMenuShow = useLastCallback((e: React.MouseEvent | React.TouchEvent) => {
    stopEvent(e);

    let x: number;
    if (e.type.startsWith('touch')) {
      const { changedTouches, touches } = e as React.TouchEvent;
      if (touches.length > 0) {
        x = touches[0].clientX;
      } else {
        x = changedTouches[0].clientX;
      }
    } else {
      x = (e as React.MouseEvent).clientX;
    }
    const { top, bottom } = e.currentTarget.getBoundingClientRect();
    const menuHeight = menuItems.length * MENU_ITEM_HEIGHT_PX;
    const screenHeight = windowSize.get().height;
    if (bottom + menuHeight + MENU_VERTICAL_OFFSET_PX + COMFORT_MARGIN_PX >= screenHeight) {
      setMenuPositionY('bottom');
      setMenuAnchor({ x, y: top });
    } else {
      setMenuPositionY('top');
      setMenuAnchor({ x, y: bottom + MENU_VERTICAL_OFFSET_PX });
    }
  });

  return {
    isActionsMenuOpen,
    menuAnchor,
    menuPositionY,
    menuItems,
    handleMenuShow,
    handleMenuItemSelect,
    closeActionsMenu,
  };
}
