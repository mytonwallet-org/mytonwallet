import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { TabWithProperties } from '../ui/TabList';

import { ANIMATED_STICKER_SMALL_SIZE_PX, MNEMONIC_COUNT, MNEMONIC_COUNTS, PRIVATE_KEY_HEX_LENGTH } from '../../config';
import { requestMeasure } from '../../lib/fasterdom/fasterdom';
import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { getIsClipboardReadDenied, readClipboardContent } from '../../util/clipboard';
import getTestId from '../../util/getTestId';
import isMnemonicPrivateKey from '../../util/isMnemonicPrivateKey';
import { compact } from '../../util/iteratees';
import { formatEnumeration } from '../../util/langProvider';
import { animateContentShift } from '../../util/layoutChangeAnimation';
import { toNativeDigits } from '../../util/nativeDigits';
import { IS_CLIPBOARDS_SUPPORTED, REM } from '../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useClipboardPaste from '../../hooks/useClipboardPaste';
import useHeightChange from '../../hooks/useHeightChange';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import InputMnemonic from '../common/InputMnemonic';
import { HEADER_HEIGHT_REM } from '../main/sections/Header/Header';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import TabList from '../ui/TabList';
import TextDivider from '../ui/TextDivider';
import Header from './Header';

import styles from './Auth.module.scss';

interface OwnProps {
  isActive?: boolean;
}

type StateProps = {
  error?: string;
  isLoading?: boolean;
};

const MNEMONIC_INPUTS = [...Array(MNEMONIC_COUNT)].map((_, index) => ({
  id: index,
  label: `${index + 1}`,
}));
const HAS_MODE_SWITCHER = MNEMONIC_COUNTS.length > 1;
const MAX_LENGTH = PRIVATE_KEY_HEX_LENGTH;
const SLIDE_ANIMATION_DURATION_MS = 250;
// Matches the `.opacity-transition` duration
const PASTE_HIDE_DURATION_MS = 150;
const SCROLL_CONTAINER_SELECTOR = `.${styles.container}`;

const AuthImportMnemonic = ({ isActive, isLoading, error }: OwnProps & StateProps) => {
  const {
    afterImportMnemonic,
    resetAuth,
    cleanAuthError,
    showToast,
  } = getActions();

  const lang = useLang();
  const containerRef = useRef<HTMLDivElement>();
  const headerRef = useRef<HTMLDivElement>();
  const pasteBlockRef = useRef<HTMLDivElement>();
  const contentRef = useRef<HTMLDivElement>();
  const footerRef = useRef<HTMLDivElement>();
  const scrollTopBeforePasteRemovalRef = useRef<number>();
  const [isPasteAvailable, setIsPasteAvailable] = useState(IS_CLIPBOARDS_SUPPORTED);
  const [mnemonic, setMnemonic] = useState<Record<number, string>>({});
  const [selectedMnemonicCount, setSelectedMnemonicCount] = useState(MNEMONIC_COUNTS[0]);

  // Called right before the paste block is removed from the page
  const handlePasteHidden = useLastCallback(() => {
    scrollTopBeforePasteRemovalRef.current = containerRef.current!.scrollTop;
  });

  const { shouldRender: shouldRenderPaste, ref: pasteRef } = useShowTransition({
    isOpen: isPasteAvailable,
    withShouldRender: true,
    noMountTransition: true,
    closeDuration: PASTE_HIDE_DURATION_MS,
    onCloseAnimationEnd: handlePasteHidden,
  });

  const handleMnemonicSet = useLastCallback((pastedMnemonic: string[]) => {
    if (!MNEMONIC_COUNTS.includes(pastedMnemonic.length) && !isMnemonicPrivateKey(pastedMnemonic)) {
      return;
    }

    cleanAuthError();

    if (MNEMONIC_COUNTS.includes(pastedMnemonic.length)) {
      setSelectedMnemonicCount(pastedMnemonic.length);
    }

    // RAF is a workaround for several Android browsers (e.g. Vivaldi)
    requestAnimationFrame(() => {
      setMnemonic(pastedMnemonic);
    });

    if (document.activeElement?.id.startsWith('import-mnemonic-')) {
      (document.activeElement as HTMLInputElement).blur();
    }
  });

  const handlePasteMnemonic = useLastCallback((pastedText: string) => {
    const pastedMnemonic = parsePastedText(pastedText);

    if (pastedMnemonic.length === 1 && document.activeElement?.id.startsWith('import-mnemonic-')) {
      (document.activeElement as HTMLInputElement).value = pastedMnemonic[0];

      const event = new Event('input');
      (document.activeElement as HTMLInputElement).dispatchEvent(event);

      return;
    }

    handleMnemonicSet(pastedMnemonic);
  });

  useClipboardPaste(Boolean(isActive), handlePasteMnemonic);

  const handlePasteMnemonicClick = useLastCallback(async () => {
    try {
      const { type, text } = await readClipboardContent();

      if (type === 'text/plain') {
        const newValue = text.trim();

        handlePasteMnemonic(newValue);
      }
    } catch {
      showToast({ message: lang('Error reading clipboard') });

      if (await getIsClipboardReadDenied()) {
        setIsPasteAvailable(false);
      }
    }
  });

  // The paste block disappears instantly, and the content below slides up with `transform`
  const handlePasteBlockHeightChange = useLastCallback((prevHeight: number, nextHeight: number) => {
    const offset = prevHeight - nextHeight;
    const container = containerRef.current!;
    const content = contentRef.current!;
    const footer = footerRef.current!;
    const containerRect = container.getBoundingClientRect();
    const scrollTopBefore = scrollTopBeforePasteRemovalRef.current ?? container.scrollTop;
    // How far the content moved up on screen. When scrolled to the bottom, the browser also reduces `scrollTop`,
    // which moves the content back down a bit.
    const visibleShift = offset - (scrollTopBefore - container.scrollTop);
    const headerBottom = containerRect.top + HEADER_HEIGHT_REM * REM;

    // The block was out of sight (scrolled away or under the header), so only the scroll is corrected
    // and nothing moves on screen. `.custom-scroll` scrolls smoothly, so the scroll is made instant.
    if (content.getBoundingClientRect().top + visibleShift < headerBottom) {
      container.scrollTo({ top: scrollTopBefore - offset, behavior: 'instant' });
      return;
    }

    // A footer stuck to the bottom stays put, a footer right below the inputs moves with them
    const footerShift = Math.min(offset, containerRect.bottom - footer.getBoundingClientRect().bottom);

    animateContentShift(content, SCROLL_CONTAINER_SELECTOR, visibleShift);
    if (footerShift > 0) {
      animateContentShift(footer, SCROLL_CONTAINER_SELECTOR, footerShift);
    }
  });

  useHeightChange(pasteBlockRef, handlePasteBlockHeightChange);

  const isSubmitDisabled = useMemo(() => {
    const filledCount = MNEMONIC_INPUTS
      .slice(0, selectedMnemonicCount)
      .filter(({ id }) => Boolean(mnemonic[id]))
      .length;
    const isPrivateKey = isMnemonicPrivateKey(compact(Object.values(mnemonic)));

    return (filledCount !== selectedMnemonicCount && !isPrivateKey) || !!error;
  }, [mnemonic, selectedMnemonicCount, error]);

  const handleSetWord = useLastCallback((value: string, index: number) => {
    cleanAuthError();
    const pastedMnemonic = parsePastedText(value);
    if (MNEMONIC_COUNTS.includes(pastedMnemonic.length)) {
      handleMnemonicSet(pastedMnemonic);
      return;
    }

    setMnemonic({
      ...mnemonic,
      [index]: pastedMnemonic[0].toLowerCase(),
    });
  });

  const handleSwitchMode = useLastCallback((index: number) => {
    const nextCount = MNEMONIC_COUNTS[index];
    if (nextCount === selectedMnemonicCount) return;

    cleanAuthError();
    setSelectedMnemonicCount(nextCount);

    // Refocus the first empty field within the new range (parity with native iOS)
    requestMeasure(() => {
      requestMeasure(() => {
        const firstEmpty = MNEMONIC_INPUTS.slice(0, nextCount).find(({ id }) => !mnemonic[id]?.trim());
        const targetId = firstEmpty ? firstEmpty.id : 0;
        document.getElementById(`import-mnemonic-${targetId}`)?.focus();
      });
    });
  });

  const handleCancel = useLastCallback(() => {
    setTimeout(() => {
      resetAuth();
    }, SLIDE_ANIMATION_DURATION_MS);
  });

  const handleSubmit = useLastCallback(() => {
    if (isSubmitDisabled) return;

    const mnemonicValues = MNEMONIC_INPUTS
      .slice(0, selectedMnemonicCount)
      .map(({ id }) => mnemonic[id])
      .filter(Boolean)
      .map((word) => word.trim().toLowerCase());

    afterImportMnemonic({ mnemonic: mnemonicValues });
  });

  useHistoryBack({
    isActive,
    onBack: handleCancel,
  });

  useEffect(() => {
    return isSubmitDisabled || isLoading
      ? undefined
      : captureKeyboardListeners({
        onEnter: { handler: handleSubmit, noStopPropagation: true },
      });
  }, [handleSubmit, isLoading, isSubmitDisabled, mnemonic, selectedMnemonicCount]);

  const modeTabs = useMemo<TabWithProperties[]>(() => MNEMONIC_COUNTS.map((count, index) => ({
    id: index,
    title: toNativeDigits(count === 12 ? lang('12 Words') : lang('24 Words')),
    className: styles.modeTab,
    testId: getTestId(`import_mode_${count}`),
  })), [lang]);
  const activeModeIndex = MNEMONIC_COUNTS.indexOf(selectedMnemonicCount);

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        // No title in the header: the 12/24 switch sticks there instead
        title={HAS_MODE_SWITCHER ? undefined : lang('Enter Secret Words')}
        topTargetRef={headerRef}
        actionIcon={IS_CLIPBOARDS_SUPPORTED ? 'icon-paste' : undefined}
        actionLabel={lang('Paste from Clipboard')}
        actionTargetRef={pasteBlockRef}
        onBackClick={handleCancel}
        onActionClick={isPasteAvailable ? handlePasteMnemonicClick : undefined}
      />
      <div
        ref={containerRef}
        className={buildClassName(
          styles.container,
          styles.container_scrollable,
          styles.importContainer,
          'custom-scroll',
        )}
      >
        <AnimatedIconWithPreview
          play={isActive}
          size={ANIMATED_STICKER_SMALL_SIZE_PX}
          tgsUrl={ANIMATED_STICKERS_PATHS.snitch}
          previewUrl={ANIMATED_STICKERS_PATHS.snitchPreview}
          nonInteractive
          noLoop={false}
          className={buildClassName(styles.topSticker, styles.importSticker)}
        />
        <div ref={headerRef} className={buildClassName(styles.title, styles.importTitle)}>
          {lang('Enter Secret Words')}
        </div>
        <div className={buildClassName(styles.info, styles.importInfo)}>
          {renderText(lang('$auth_import_mnemonic_description', {
            counts: toNativeDigits(formatEnumeration(lang, [...MNEMONIC_COUNTS], 'or', true)),
          }))}
        </div>

        <div ref={pasteBlockRef} className={styles.pasteBlock}>
          {shouldRenderPaste && (
            <div ref={pasteRef}>
              <Button
                isPrimary
                testId={getTestId('import_paste')}
                className={styles.pasteButton}
                onClick={handlePasteMnemonicClick}
              >
                <i className={buildClassName(styles.pasteButtonIcon, 'icon-paste')} aria-hidden />
                <span className={styles.pasteButtonText}>{lang('Paste from Clipboard')}</span>
              </Button>
              <TextDivider className={styles.divider}>{lang('or enter manually')}</TextDivider>
            </div>
          )}
        </div>

        <div ref={contentRef} className={styles.importContent}>
          {HAS_MODE_SWITCHER && (
            <div className={styles.modeSwitchRoot}>
              <TabList
                tabs={modeTabs}
                activeTab={activeModeIndex}
                className={styles.modeSwitch}
                overlayClassName={styles.modeSwitchOverlay}
                onSwitchTab={handleSwitchMode}
              />
            </div>
          )}

          <div
            className={buildClassName(
              styles.importingContent,
              selectedMnemonicCount === 12 && styles.importingContent_short,
            )}
            dir="ltr"
          >
            {MNEMONIC_INPUTS.slice(0, selectedMnemonicCount).map(({ id, label }, i) => (
              <InputMnemonic
                key={id}
                id={`import-mnemonic-${id}`}
                testId={getTestId(`import_word_${id + 1}`)}
                nextId={id + 1 < selectedMnemonicCount ? `import-mnemonic-${id + 1}` : undefined}
                labelText={label}
                value={mnemonic[id]}
                inputArg={id}
                onInput={handleSetWord}
                onEnter={i === selectedMnemonicCount - 1 ? handleSubmit : undefined}
              />
            ))}
          </div>
        </div>

        <div ref={footerRef} className={styles.importFooter}>
          {error && <div className={styles.footerError}>{lang(error)}</div>}
          <div className={styles.importFooterButton}>
            <Button
              isPrimary
              testId={getTestId('import_continue')}
              isDisabled={isSubmitDisabled}
              isLoading={isLoading}
              className={styles.btn}
              onClick={handleSubmit}
            >
              {lang('Continue')}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    error: global.auth.error,
    isLoading: global.auth.isLoading,
  };
})(AuthImportMnemonic));

function parsePastedText(str = '') {
  return str
    .replace(/(?:\r\n)+|[\r\n\s;,\t]+/g, ' ')
    .trim()
    .toLowerCase()
    .split(' ')
    .map((w) => w.slice(0, MAX_LENGTH));
}
