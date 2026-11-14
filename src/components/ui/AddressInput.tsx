import type { ClipboardEvent, HTMLAttributes } from 'react';
import React, {
  type ElementRef,
  memo,
  useEffect,
  useMemo,
  useRef,
  useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';
import type { Account, SavedAddress } from '../../global/types';

import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectNetworkAccounts,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getSupportedChains } from '../../util/chain';
import { readClipboardContent } from '../../util/clipboard';
import { isTonChainDns } from '../../util/dns';
import { getLocalAddressName } from '../../util/getLocalAddressName';
import { isTonsiteAddress, isValidAddressOrDomain } from '../../util/isValidAddress';
import { shortenAddress } from '../../util/shortenAddress';
import { getHostnameFromUrl } from '../../util/url';
import {
  getIsMobileTelegramApp,
  IS_ANDROID,
  IS_CLIPBOARDS_SUPPORTED,
  IS_IOS,
} from '../../util/windowEnvironment';

import useDebouncedValue from '../../hooks/useDebouncedValue';
import useEffectOnce from '../../hooks/useEffectOnce';
import useFlag from '../../hooks/useFlag';
import useKeyboardListNavigation from '../../hooks/useKeyboardListNavigation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useQrScannerSupport from '../../hooks/useQrScannerSupport';
import useUniqueId from '../../hooks/useUniqueId';
import useAddressBookItems from './hooks/useAddressBookItems';

import DeleteSavedAddressModal from '../main/modals/DeleteSavedAddressModal';
import AddressBook from './AddressBook';
import { SUGGESTION_ITEM_CLASS_NAME } from './AddressBookItem';
import Button from './Button';
import Input from './Input';
import Transition from './Transition';

import styles from './AddressInput.module.scss';

export const INPUT_CLEAR_BUTTON_ID = 'input-clear-button';

interface OwnProps {
  ref?: ElementRef<HTMLInputElement | HTMLTextAreaElement>;
  testId?: string;
  label?: string;
  value: string;
  chain?: ApiChain;
  isStatic?: boolean;
  isReadonly?: boolean;
  withQrScan?: boolean;
  withCurrentAccount?: boolean;
  shouldHideAddressBook?: boolean;
  shouldValidateAllChains?: boolean;
  address: string;
  addressName: string;
  addressBookChain?: ApiChain;
  savedAddresses?: SavedAddress[];
  validateAddress?: ({ address }: { address?: string; chain?: ApiChain }) => void;
  /** Paints the address red for an error that the form explains elsewhere, for example on its submit button */
  hasError?: boolean;
  error?: string;
  enterKeyHint?: HTMLAttributes<HTMLInputElement>['enterKeyHint'];
  onInput: (value: string, isValueReplaced?: boolean) => void;
  onPaste?: (value: string) => void;
  /**
   * Reports the result of the field's own format check. The check runs on blur, on paste, on a chain change,
   * and when the form replaces the value while an error is shown. Focus and typing clear the error.
   * A form that passes it explains the error itself, for example on its submit button, and the field only paints
   * the address red. Without it, the field shows the error text.
   */
  onError?: (hasError: boolean) => void;
  onClose: NoneToVoidFunction;
}

interface StateProps {
  currentAccountId: string | undefined;
  savedAddresses?: SavedAddress[];
  accounts?: Record<string, Account>;
  supportedChains?: Partial<Record<ApiChain, unknown>>;
  orderedAccountIds?: string[];
}

const SHORT_ADDRESS_SHIFT = 4;
const SHORT_SINGLE_ADDRESS_SHIFT = 11;
const MIN_ADDRESS_LENGTH_TO_SHORTEN = SHORT_SINGLE_ADDRESS_SHIFT * 2;
const SAVED_ADDRESS_OPEN_DELAY = 300;
const SEARCH_DEBOUNCE_MS = 200;

function AddressInput({
  ref,
  testId,
  label,
  value,
  chain,
  isStatic,
  isReadonly,
  withQrScan,
  withCurrentAccount,
  shouldHideAddressBook,
  shouldValidateAllChains,
  address,
  addressName,
  addressBookChain,
  accounts,
  currentAccountId = '',
  savedAddresses,
  supportedChains,
  orderedAccountIds,
  validateAddress,
  hasError,
  error,
  enterKeyHint,
  onInput,
  onPaste,
  onError,
  onClose,
}: OwnProps & StateProps) {
  const {
    showToast,
    requestOpenQrScanner,
  } = getActions();

  const lang = useLang();

  const addressBookTimeoutRef = useRef<number>();
  const isAddressBookSelectionRef = useRef<boolean>(false);

  const [addressForDeletion, setAddressForDeletion] = useState<string | undefined>();
  const [chainForDeletion, setChainForDeletion] = useState<ApiChain | undefined>();
  const [hasLocalError, setHasLocalError] = useState(false);

  const [isAddressBookOpen, openAddressBook, closeAddressBook] = useFlag();
  const [isFocused, markFocused, unmarkFocused] = useFlag();
  const [shouldRenderPasteButton, setShouldRenderPasteButton] = useState(IS_CLIPBOARDS_SUPPORTED);
  const isQrScannerSupported = useQrScannerSupport();
  const inputId = useUniqueId('address-');

  const searchValue = useDebouncedValue(value, SEARCH_DEBOUNCE_MS);

  const addressBookAccountIds = useMemo(() => {
    if (!accounts) return [];

    const allAccountIds = Object.keys(accounts);

    return withCurrentAccount
      ? allAccountIds
      : allAccountIds.filter((accountId) => accountId !== currentAccountId);
  }, [currentAccountId, accounts, withCurrentAccount]);

  const shouldUseAddressBook = useMemo(() => {
    return !shouldHideAddressBook
      && (addressBookAccountIds.length > 0 || (savedAddresses && savedAddresses.length > 0));
  }, [shouldHideAddressBook, addressBookAccountIds.length, savedAddresses]);

  const localAddressName = useMemo(() => {
    return chain && value ? getLocalAddressName({
      address: value,
      chain,
      currentAccountId,
      savedAddresses,
      accounts: accounts!,
    }) : undefined;
  }, [accounts, chain, currentAccountId, savedAddresses, value]);

  const addressBookItems = useAddressBookItems({
    savedAddresses,
    accounts,
    supportedChains,
    otherAccountIds: addressBookAccountIds,
    currentChain: addressBookChain,
    searchValue,
    orderedAccountIds,
  });

  const handleAddressBookItemSelect = useLastCallback((address: string) => {
    isAddressBookSelectionRef.current = true;
    changeError(false);
    onInput(address, true);
    onPaste?.(address);
    closeAddressBook();
  });

  const {
    activeIndex,
    listRef: menuRef,
    handleKeyDown,
    resetIndex,
  } = useKeyboardListNavigation(
    isAddressBookOpen,
    (index) => {
      const item = addressBookItems[index];
      if (item) {
        handleAddressBookItemSelect(item.address);
      }
    },
    `.${SUGGESTION_ITEM_CLASS_NAME}`,
  );

  const isLocalErrorExplainedByForm = Boolean(onError);
  const hasValueError = (hasLocalError && isLocalErrorExplainedByForm) || hasError;
  const localErrorText = hasLocalError && !isLocalErrorExplainedByForm ? lang('Incorrect address') : undefined;
  const withPasteButton = shouldRenderPasteButton && !value;
  const withQrButton = withQrScan && isQrScannerSupported;
  const withButton = (withQrButton || withPasteButton || !!value.length) && !isReadonly;

  useEffectOnce(() => {
    return () => {
      if (addressBookTimeoutRef.current) {
        window.clearTimeout(addressBookTimeoutRef.current);
      }
    };
  });

  useEffect(() => {
    if (value) {
      handleAddressErrorCheck(value);
    }
    // Only re-validate when chain changes, not on every value change
    // eslint-disable-next-line react-hooks-static-deps/exhaustive-deps
  }, [chain]);

  // The form can replace the value without the user, for example by clearing itself or applying a scanned QR code.
  // A shown error must describe the current value, so it is checked again.
  useEffect(() => {
    if (!hasLocalError) return;

    if (value) {
      handleAddressErrorCheck(value);
    } else {
      changeError(false);
    }
    // eslint-disable-next-line react-hooks-static-deps/exhaustive-deps
  }, [value]);

  const addressOverlay = useMemo(() => {
    if (!address) return undefined;
    const renderedAddressName = localAddressName || addressName;

    const addressShort = !renderedAddressName && address.length > MIN_ADDRESS_LENGTH_TO_SHORTEN
      ? shortenAddress(address, SHORT_SINGLE_ADDRESS_SHIFT) || ''
      : address;

    return (
      <>
        {renderedAddressName && <span className={styles.addressName}>{renderedAddressName}</span>}
        <span className={buildClassName(styles.addressValue, !renderedAddressName && styles.addressValueSingle)}>
          {renderedAddressName ? shortenAddress(address, SHORT_ADDRESS_SHIFT) : addressShort}
        </span>
      </>
    );
  }, [address, localAddressName, addressName]);

  function changeError(hasNewError: boolean) {
    setHasLocalError(hasNewError);
    onError?.(hasNewError);
  }

  const handlePasteClick = useLastCallback(async () => {
    try {
      const { type, text } = await readClipboardContent();

      if (type === 'text/plain') {
        const newValue = cleanTonsiteAddress(text.trim());
        onInput(newValue, true);
        onPaste?.(newValue);

        handleAddressValidate(newValue);
        handleAddressErrorCheck(newValue);
      }
    } catch (err: any) {
      showToast({ message: lang('Error reading clipboard') });
      setShouldRenderPasteButton(false);
    }
  });

  const handleQrScanClick = useLastCallback(() => {
    if (IS_IOS && getIsMobileTelegramApp()) {
      alert('Scanning is temporarily not available');
      return;
    }

    requestOpenQrScanner();
    onClose();
  });

  const handleAddressValidate = useLastCallback((address?: string) => {
    if (!validateAddress) return;

    if (address) {
      address = cleanTonsiteAddress(address);
    }

    if ((address && chain && isValidAddressOrDomain(address, chain)) || !address) {
      validateAddress({ address, chain });
    }
  });

  function handleAddressErrorCheck(address?: string) {
    // Skip error check if address was just selected from AddressBook
    if (isAddressBookSelectionRef.current) {
      isAddressBookSelectionRef.current = false;
      return;
    }

    if (!address) return;

    let isAddressValid: boolean | undefined;
    if (chain) {
      isAddressValid = isValidAddressOrDomain(address, chain);
    } else if (shouldValidateAllChains) {
      isAddressValid = getSupportedChains().some((c) => isValidAddressOrDomain(address, c));
    }
    changeError(isAddressValid !== undefined && address.length > 0 && !isAddressValid);
  }

  const handleAddressFocus = useLastCallback(() => {
    markFocused();
    changeError(false);

    if (shouldUseAddressBook) {
      // Simultaneous opening of the virtual keyboard and display of Saved Addresses causes animation degradation
      if (IS_ANDROID) {
        addressBookTimeoutRef.current = window.setTimeout(openAddressBook, SAVED_ADDRESS_OPEN_DELAY);
      } else {
        openAddressBook();
      }
    }
  });

  const handleAddressBlur = useLastCallback((e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    unmarkFocused();

    if (e.relatedTarget?.id === INPUT_CLEAR_BUTTON_ID) {
      handleAddressBookClose();
      handleAddressValidate(value);
      handleAddressErrorCheck(value);

      return;
    }

    let addressToCheck = cleanTonsiteAddress(value);
    if (isTonChainDns(value) && value !== value.toLowerCase()) {
      addressToCheck = value.toLowerCase().trim();
      onInput(addressToCheck);
    } else if (value !== value.trim()) {
      addressToCheck = value.trim();
      onInput(addressToCheck);
    }

    requestAnimationFrame(() => {
      handleAddressBookClose();
      handleAddressValidate(addressToCheck);
      handleAddressErrorCheck(addressToCheck);
    });
  });

  function hanldeInputChange(value: string) {
    onInput(value);
    changeError(false);
  }

  const handleAddressPaste = useLastCallback((event: ClipboardEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    event.preventDefault();
    let value = event.clipboardData.getData('text').trim();
    value = cleanTonsiteAddress(value);
    onInput(value, false);
    onPaste?.(value);
    handleAddressErrorCheck(value);
  });

  const handleAddressClear = useLastCallback(() => {
    onInput('');
    handleAddressValidate();
    changeError(false);
  });

  const handleAddressBookClose = useLastCallback(() => {
    if (!shouldUseAddressBook || !isAddressBookOpen) return;

    closeAddressBook();
    resetIndex();

    if (addressBookTimeoutRef.current) {
      window.clearTimeout(addressBookTimeoutRef.current);
    }
  });

  const handleDeleteSavedAddressClick = useLastCallback((address: string) => {
    setAddressForDeletion(address);
    setChainForDeletion(chain);
    closeAddressBook();
  });

  const handleDeleteSavedAddressModalClose = useLastCallback(() => {
    setAddressForDeletion(undefined);
    setChainForDeletion(undefined);
  });

  function renderInputActions() {
    const wrapperClassName = buildClassName(
      styles.inputButtonWrapper,
      isFocused && styles.inputButtonWrapperWithFocus,
    );

    return (
      <Transition className={styles.inputButtonTransition} activeKey={value.length ? 0 : 1} name="fade">
        {value.length ? (
          <div className={wrapperClassName}>
            <Button
              isSimple
              id={INPUT_CLEAR_BUTTON_ID}
              className={buildClassName(styles.inputButton, styles.inputButtonClear)}
              onClick={handleAddressClear}
              ariaLabel={lang('Clear')}
            >
              <i className="icon-close-filled" aria-hidden />
            </Button>
          </div>
        ) : (
          <div className={wrapperClassName}>
            {withQrButton && (
              <Button
                isSimple
                className={styles.inputButton}
                onClick={handleQrScanClick}
                ariaLabel={lang('Scan QR Code')}
              >
                <i className="icon-qr-scanner-alt" aria-hidden />
              </Button>
            )}
            {withPasteButton && (
              <Button isSimple className={styles.inputButton} onClick={handlePasteClick} ariaLabel={lang('Paste')}>
                <i className="icon-paste" aria-hidden />
              </Button>
            )}
          </div>
        )}
      </Transition>
    );
  }

  return (
    <>
      <Input
        id={inputId}
        ref={ref}
        testId={testId}
        className={buildClassName(isStatic && styles.inputStatic, withButton && styles.inputWithIcon)}
        isRequired
        isStatic={isStatic}
        isDisabled={isReadonly}
        label={label}
        placeholder={lang('Wallet address or domain')}
        value={value}
        hasValueError={hasValueError}
        error={localErrorText || error}
        autoCorrect={false}
        enterKeyHint={enterKeyHint}
        // The overlay shows a shortened address in neutral colors, so an invalid value goes without it
        valueOverlay={!hasLocalError && !hasError ? addressOverlay : undefined}
        onInput={hanldeInputChange}
        onPaste={handleAddressPaste}
        onKeyDown={handleKeyDown}
        onFocus={handleAddressFocus}
        onBlur={handleAddressBlur}
      >
        {!isReadonly && renderInputActions()}
      </Input>
      {shouldUseAddressBook && (
        <>
          <AddressBook
            isOpen={isAddressBookOpen}
            items={addressBookItems}
            menuRef={menuRef}
            activeIndex={activeIndex}
            onAddressSelect={handleAddressBookItemSelect}
            onSavedAddressDelete={handleDeleteSavedAddressClick}
            onClose={closeAddressBook}
          />
          <DeleteSavedAddressModal
            isOpen={Boolean(addressForDeletion)}
            address={addressForDeletion}
            chain={chainForDeletion}
            onClose={handleDeleteSavedAddressModalClose}
          />
        </>
      )}
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const currentAccountId = selectCurrentAccountId(global);
  const account = selectCurrentAccount(global);
  const accountState = selectCurrentAccountState(global);

  return {
    savedAddresses: accountState?.savedAddresses,
    supportedChains: account?.byChain,
    accounts: selectNetworkAccounts(global),
    currentAccountId,
    orderedAccountIds: global.settings.orderedAccountIds,
  };
})(AddressInput));

function cleanTonsiteAddress(address: string) {
  if (isTonsiteAddress(address)) {
    return getHostnameFromUrl(address);
  } else {
    return address;
  }
}
