import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { ANIMATED_STICKER_SMALL_SIZE_PX, MNEMONIC_COUNT, MNEMONIC_COUNTS, PRIVATE_KEY_HEX_LENGTH } from '../../config';
import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { readClipboardContent } from '../../util/clipboard';
import isMnemonicPrivateKey from '../../util/isMnemonicPrivateKey';
import { compact } from '../../util/iteratees';
import { formatEnumeration } from '../../util/langProvider';
import { IS_CLIPBOARDS_SUPPORTED } from '../../util/windowEnvironment';
import { callApi } from '../../api';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useClipboardPaste from '../../hooks/useClipboardPaste';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import InputMnemonic from '../common/InputMnemonic';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
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
    const mnemonicValues = compact(Object.values(mnemonic));

    return (!MNEMONIC_COUNTS.includes(mnemonicValues.length) && !isMnemonicPrivateKey(mnemonicValues))
      || !!error;
  }, [mnemonic, error]);

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

  const handleCancel = useLastCallback(() => {
    setTimeout(() => {
      resetAuth();
    }, SLIDE_ANIMATION_DURATION_MS);
  });

  const handleSubmit = useLastCallback(async () => {
    if (isSubmitDisabled) return;

    const mnemonicValues = compact(Object.values(mnemonic))
      .map((word) => word.trim().toLowerCase())
      .filter(Boolean);

    if (mnemonicValues.length === 12) {
      const isShortMnemonicValid = await callApi('validateMnemonic', mnemonicValues);
      if (!isShortMnemonicValid) return;
    }

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
  }, [handleSubmit, isLoading, isSubmitDisabled, mnemonic]);

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

        <div className={styles.importingContent}>
          {MNEMONIC_INPUTS.map(({ id, label }, i) => (
            <InputMnemonic
              key={id}
              id={`import-mnemonic-${id}`}
              nextId={id + 1 < MNEMONIC_COUNT ? `import-mnemonic-${id + 1}` : undefined}
              labelText={label}
              value={mnemonic[id]}
              inputArg={id}
              onInput={handleSetWord}
              onEnter={i === MNEMONIC_COUNT - 1 ? handleSubmit : undefined}
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
