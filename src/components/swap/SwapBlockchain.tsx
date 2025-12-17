import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions } from '../../global';

import { SwapState, SwapType, type UserSwapToken } from '../../global/types';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../../config';
import buildClassName from '../../util/buildClassName';
import { readClipboardContent } from '../../util/clipboard';
import { vibrate } from '../../util/haptics';
import { shortenAddress } from '../../util/shortenAddress';
import getChainNetworkName from '../../util/swap/getChainNetworkName';
import { getIsMobileTelegramApp, IS_CLIPBOARDS_SUPPORTED, IS_IOS } from '../../util/windowEnvironment';
import { callApi } from '../../api';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useFlag from '../../hooks/useFlag';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useQrScannerSupport from '../../hooks/useQrScannerSupport';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Input from '../ui/Input';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Swap.module.scss';

interface OwnProps {
  isActive: boolean;
  swapType?: SwapType;
  toAddress?: string;
  tokenIn?: UserSwapToken;
  tokenOut?: UserSwapToken;
}

const SHORT_ADDRESS_SHIFT = 14;
const MIN_ADDRESS_LENGTH_TO_SHORTEN = SHORT_ADDRESS_SHIFT * 2;

function SwapBlockchain({
  isActive,
  swapType,
  toAddress = '',
  tokenIn,
  tokenOut,
}: OwnProps) {
  const {
    cancelSwap,
    setSwapCexAddress,
    showToast,
    setSwapScreen,
    requestOpenQrScanner,
  } = getActions();
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();

  const toAddressRef = useRef<HTMLInputElement>();

  const [shouldRenderPasteButton, setShouldRenderPasteButton] = useState(IS_CLIPBOARDS_SUPPORTED);
  const [isAddressFocused, markAddressFocused, unmarkAddressFocused] = useFlag();
  const [hasToAddressError, setHasToAddressError] = useState(false);
  const [canContinue, setCanContinue] = useState(false);

  const isQrScannerSupported = useQrScannerSupport();

  const withPasteButton = shouldRenderPasteButton && toAddress === '';

  const toAddressShort = toAddress.length > MIN_ADDRESS_LENGTH_TO_SHORTEN
    ? shortenAddress(toAddress, SHORT_ADDRESS_SHIFT) || ''
    : toAddress;

  const handleCancelClick = useLastCallback(() => {
    setHasToAddressError(false);
    setCanContinue(false);
    setSwapScreen({ state: isPortrait ? SwapState.Initial : SwapState.None });
  });

  useHistoryBack({
    isActive,
    onBack: handleCancelClick,
  });

  const handleAddressFocus = useLastCallback(() => {
    const el = toAddressRef.current!;

    // `selectionStart` is only updated in the next frame after `focus` event
    requestAnimationFrame(() => {
      const caretPosition = el.selectionStart!;
      markAddressFocused();

      // Restore caret position after input field value has been focused and expanded
      requestAnimationFrame(() => {
        const newCaretPosition = caretPosition <= SHORT_ADDRESS_SHIFT + 3
          ? caretPosition
          : Math.max(0, el.value.length - (toAddressShort.length - caretPosition));

        el.setSelectionRange(newCaretPosition, newCaretPosition);
        if (newCaretPosition > SHORT_ADDRESS_SHIFT * 2) {
          el.scrollLeft = el.scrollWidth - el.clientWidth;
        }
      });
    });
  });

  const validateToAddress = useLastCallback(async (address: string) => {
    if (!address.length) {
      setHasToAddressError(false);
      setCanContinue(false);
      return;
    }

    const response = await callApi('swapCexValidateAddress', {
      slug: tokenOut!.slug,
      address,
    });

    if (!response) {
      setHasToAddressError(false);
      setCanContinue(false);
      return;
    }

    setHasToAddressError(!response.result);
    setCanContinue(response.result);
  });

  const handleAddressBlur = useLastCallback(() => {
    unmarkAddressFocused();
  });

  const handleAddressInput = useLastCallback((newToAddress: string) => {
    setSwapCexAddress({ toAddress: newToAddress.trim() });
  });

  const handlePasteClick = useLastCallback(async () => {
    try {
      const { type, text } = await readClipboardContent();

      if (type === 'text/plain') {
        setSwapCexAddress({ toAddress: text.trim() });
        await validateToAddress(text.trim());
      }
    } catch (error) {
      showToast({
        message: lang('Error reading clipboard'),
      });
      setShouldRenderPasteButton(false);
    }
  });

  useEffect(() => {
    void validateToAddress(toAddress);
  }, [toAddress, validateToAddress]);

  const submitPassword = useLastCallback(() => {
    void vibrate();
    setSwapScreen({ state: SwapState.Password });
  });

  const handleQrScanClick = useLastCallback(() => {
    if (IS_IOS && getIsMobileTelegramApp()) {
      alert('Scanning is temporarily not available');
      return;
    }

    requestOpenQrScanner();
    cancelSwap();
  });

  function renderInfo() {
    const text = hasToAddressError
      ? lang('Incorrect address.')
      : lang('Please provide an address of your wallet in %blockchain% blockchain to receive bought tokens.', {
        blockchain: getChainNetworkName(tokenOut?.chain),
      });

    return (
      <Transition
        name="fade"
        activeKey={hasToAddressError ? 0 : 1}
        slideClassName={styles.blockchainHintWrapper}
      >
        <span className={buildClassName(
          styles.blockchainHintText,
          hasToAddressError && styles.blockchainHintTextError,
        )}
        >
          {text}
        </span>
      </Transition>
    );
  }

  function renderInputAddress() {
    if (swapType !== SwapType.CrosschainFromWallet) return undefined;

    return (
      <>
        <div className={styles.inputAddress}>
          <Input
            ref={toAddressRef}
            isRequired
            placeholder={lang('Your address on another blockchain')}
            value={isAddressFocused ? toAddress : toAddressShort}
            onInput={handleAddressInput}
            onFocus={handleAddressFocus}
            onBlur={handleAddressBlur}
            wrapperClassName={styles.inputAddressWrapper}
          >
            {isQrScannerSupported && (
              <Button
                isSimple
                className={buildClassName(styles.inputButton, withPasteButton && styles.inputButtonShifted)}
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
          </Input>
        </div>
        {renderInfo()}
      </>
    );
  }

  const title = lang('$swap_from_to', {
    from: tokenIn?.symbol,
    icon: <i className={buildClassName('icon-chevron-right', styles.swapArrowIcon)} aria-hidden />,
    to: tokenOut?.symbol,
  }) as TeactNode[];

  return (
    <>
      <ModalHeader title={title} onClose={cancelSwap} />
      <div className={buildClassName(styles.scrollContent, styles.selectBlockchainBlock, 'custom-scroll')}>
        <AnimatedIconWithPreview
          play={isActive}
          noLoop={false}
          nonInteractive
          tgsUrl={ANIMATED_STICKERS_PATHS.bill}
          previewUrl={ANIMATED_STICKERS_PATHS.billPreview}
          size={ANIMATED_STICKER_BIG_SIZE_PX}
        />

        {renderInputAddress()}

        <div className={buildClassName(styles.blockchainButtons, modalStyles.footerButtons)}>
          <Button onClick={handleCancelClick} className={modalStyles.buttonHalfWidth}>{lang('Close')}</Button>
          <Button
            isPrimary
            isDisabled={!canContinue}
            className={modalStyles.buttonHalfWidth}
            onClick={submitPassword}
          >
            {lang('Continue')}
          </Button>
        </div>
      </div>
    </>
  );
}

export default memo(SwapBlockchain);
