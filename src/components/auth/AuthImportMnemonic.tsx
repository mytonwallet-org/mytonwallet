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
import { readClipboardContent } from '../../util/clipboard';
import isMnemonicPrivateKey from '../../util/isMnemonicPrivateKey';
import { compact } from '../../util/iteratees';
import { formatEnumeration } from '../../util/langProvider';
import { IS_CLIPBOARDS_SUPPORTED } from '../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useClipboardPaste from '../../hooks/useClipboardPaste';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import InputMnemonic from '../common/InputMnemonic';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import TabList from '../ui/TabList';
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
  const [shouldRenderPasteButton, setShouldRenderPasteButton] = useState(IS_CLIPBOARDS_SUPPORTED);
  const [mnemonic, setMnemonic] = useState<Record<number, string>>({});
  const [selectedMnemonicCount, setSelectedMnemonicCount] = useState(MNEMONIC_COUNTS[0]);

  const {
    isAtEnd: noButtonsSeparator,
    update,
    handleScroll,
  } = useScrolledState();

  useEffect(() => {
    if (isActive) {
      update(containerRef.current);
    }
  }, [isActive, update]);

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
    } catch (err: any) {
      showToast({ message: lang('Error reading clipboard') });
      setShouldRenderPasteButton(false);
    }
  });
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
    title: count === 12 ? lang('12 Words') : lang('24 Words'),
    className: styles.modeTab,
  })), [lang]);
  const activeModeIndex = MNEMONIC_COUNTS.indexOf(selectedMnemonicCount);

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        title={lang('Enter Secret Words')}
        topTargetRef={headerRef}
        onBackClick={handleCancel}
      />
      <div
        ref={containerRef}
        className={buildClassName(styles.container, styles.container_scrollable, 'custom-scroll')}
        onScroll={handleScroll}
      >
        <AnimatedIconWithPreview
          play={isActive}
          size={ANIMATED_STICKER_SMALL_SIZE_PX}
          tgsUrl={ANIMATED_STICKERS_PATHS.snitch}
          previewUrl={ANIMATED_STICKERS_PATHS.snitchPreview}
          nonInteractive
          noLoop={false}
          className={styles.sticker}
        />
        <div ref={headerRef} className={buildClassName(styles.title, styles.title_afterSmallSticker)}>
          {lang('Enter Secret Words')}
        </div>
        <div className={buildClassName(styles.info, styles.infoSmallFont, styles.infoPull)}>
          {renderText(lang('$auth_import_mnemonic_description', {
            counts: formatEnumeration(lang, [...MNEMONIC_COUNTS], 'or', true),
          }))}
        </div>

        {shouldRenderPasteButton && (
          <Button isText className={styles.pasteButton} onClick={handlePasteMnemonicClick}>
            <i className={buildClassName(styles.pasteButtonIcon, 'icon-copy-bold')} aria-hidden />

            {lang('Paste from Clipboard')}
          </Button>
        )}

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

        <div className={buildClassName(
          styles.importingContent,
          selectedMnemonicCount === 12 && styles.importingContent_short,
          error && styles.importingContent_withError,
        )}
        >
          {MNEMONIC_INPUTS.slice(0, selectedMnemonicCount).map(({ id, label }, i) => (
            <InputMnemonic
              key={id}
              id={`import-mnemonic-${id}`}
              nextId={id + 1 < selectedMnemonicCount ? `import-mnemonic-${id + 1}` : undefined}
              labelText={label}
              value={mnemonic[id]}
              inputArg={id}
              onInput={handleSetWord}
              onEnter={i === selectedMnemonicCount - 1 ? handleSubmit : undefined}
            />
          ))}
        </div>

        <div className={buildClassName(
          styles.buttons,
          styles.buttonsBottomStuck,
          noButtonsSeparator && styles.buttonsNoSeparator,
        )}
        >
          <div className={styles.buttonsBottomStuckInner}>
            {error && <div className={styles.footerError}>{lang(error)}</div>}
            <Button
              isPrimary
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
