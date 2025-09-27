import React, { memo, useEffect, useMemo, useRef, useState } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import renderText from '../../../global/helpers/renderText';
import buildClassName from '../../../util/buildClassName';
import { shuffle } from '../../../util/iteratees';
import { SEC } from '../../../api/constants';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Button from '../../ui/Button';

import styles from './CheckWordsForm.module.scss';

interface OwnProps {
  isActive?: boolean;
  checkIndexes?: number[];
  mnemonic?: string[];
  descriptionClassName?: string;
  formClassName?: string;
  errorClassName?: string;
  onSubmit: AnyFunction;
  isErrorVisible?: boolean;
  // Notify parent about validation result to lift error state
  onValidationComplete?: (isCorrect: boolean) => void;
  // Notify parent to clear lifted error when user interacts
  onUserInteraction?: NoneToVoidFunction;
}

const WORDS_PER_ROW = 4;
const RESULT_DISPLAY_DURATION = SEC;

function CheckWordsForm({
  isActive,
  checkIndexes,
  mnemonic,
  descriptionClassName,
  formClassName,
  errorClassName,
  onSubmit,
  onValidationComplete,
  onUserInteraction,
  isErrorVisible,
}: OwnProps) {
  const { restartCheckMnemonicIndexes } = getActions();

  const lang = useLang();
  const [selectedWords, setSelectedWords] = useState<Record<number, string>>({});
  const [wordOptions, setWordOptions] = useState<Record<number, string[]>>({});
  const [showValidation, setShowValidation] = useState(false);
  const [validationResults, setValidationResults] = useState<Record<number, boolean>>({});
  const timeoutRef = useRef<number | undefined>(undefined);

  const generateWordOptions = useLastCallback(() => {
    if (!checkIndexes || !mnemonic || mnemonic.length === 0) return;

    const options: Record<number, string[]> = {};

    checkIndexes.forEach((index) => {
      const correctWord = mnemonic[index];
      const pool = Array.from(new Set(mnemonic.filter((word) => word !== correctWord)));
      const wrongWords = shuffle(pool).slice(0, WORDS_PER_ROW - 1);
      options[index] = shuffle([correctWord, ...wrongWords]);
    });

    setWordOptions(options);
  });

  // Generate new options when component becomes active or after error
  useEffect(() => {
    if (isActive && checkIndexes && mnemonic?.length) {
      generateWordOptions();
      setSelectedWords({});
      setShowValidation(false);
      setValidationResults({});
    }
  }, [checkIndexes, isActive, mnemonic?.length]);

  useEffect(() => () => {
    if (timeoutRef.current !== undefined) {
      window.clearTimeout(timeoutRef.current);
      timeoutRef.current = undefined;
    }
  }, []);

  const handleWordSelect = useLastCallback((word: string, index: number) => {
    setSelectedWords((prev) => ({
      ...prev,
      [index]: word,
    }));
    setShowValidation(false);
    setValidationResults({});
    // Inform parent to clear lifted error on any interaction
    onUserInteraction?.();
  });

  const handleContinue = useLastCallback(() => {
    if (!checkIndexes || !mnemonic) return;

    // Show validation results for both correct and incorrect answers
    const results: Record<number, boolean> = {};
    checkIndexes.forEach((index) => {
      results[index] = selectedWords[index] === mnemonic[index];
    });
    setValidationResults(results);
    setShowValidation(true);

    const isCorrect = checkIndexes.every((index) => selectedWords[index] === mnemonic[index]);

    if (isCorrect) {
      if (timeoutRef.current !== undefined) {
        window.clearTimeout(timeoutRef.current);
      }
      timeoutRef.current = window.setTimeout(() => {
        setShowValidation(false);
        setValidationResults({});
        onSubmit();
        timeoutRef.current = undefined;
        onValidationComplete?.(true);
      }, RESULT_DISPLAY_DURATION);
    } else {
      if (timeoutRef.current !== undefined) {
        window.clearTimeout(timeoutRef.current);
      }
      timeoutRef.current = window.setTimeout(() => {
        if (mnemonic && checkIndexes) {
          const incorrectIndexes = checkIndexes.filter((index) => selectedWords[index] !== mnemonic[index]);
          restartCheckMnemonicIndexes({
            wordsCount: mnemonic.length,
            preserveIndexes: incorrectIndexes,
          });
        }
        onValidationComplete?.(false);
        setSelectedWords({});
        setShowValidation(false);
        setValidationResults({});
        timeoutRef.current = undefined;
      }, RESULT_DISPLAY_DURATION);
    }
  });

  const isAllWordsSelected = useMemo(() => {
    return checkIndexes?.every((index) => Boolean(selectedWords[index])) ?? false;
  }, [checkIndexes, selectedWords]);

  const wordNumbers = useMemo(() => {
    return checkIndexes?.map((n) => n + 1).join(', ') ?? '';
  }, [checkIndexes]);

  return (
    <>
      <p className={descriptionClassName}>
        {renderText(lang('$mnemonic_check_words_list', {
          word_numbers: <b>{wordNumbers}</b>,
        }))}
      </p>

      <div className={formClassName}>
        {checkIndexes?.map((index) => (
          <div key={index} className={styles.wordRow}>
            <div className={buildClassName(
              styles.rowLabel,
              showValidation && validationResults[index] && styles.correct,
              showValidation && !validationResults[index] && styles.error,
            )}
            >
              {index + 1}.
            </div>
            <div className={styles.words}>
              {wordOptions[index]?.map((word) => {
                const isSelected = selectedWords[index] === word;
                const isCorrect = word === mnemonic?.[index];
                const shouldShowResult = showValidation && isSelected;

                return (
                  <button
                    key={word}
                    type="button"
                    className={buildClassName(
                      styles.word,
                      isSelected && !showValidation && styles.wordSelected,
                      shouldShowResult && isCorrect && styles.wordCorrect,
                      shouldShowResult && !isCorrect && styles.wordError,
                    )}
                    aria-pressed={isSelected}
                    disabled={showValidation}
                    onClick={!showValidation ? () => handleWordSelect(word, index) : undefined}
                  >
                    {word}
                  </button>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      <div className={buildClassName(
        styles.errorMessage,
        isErrorVisible && styles.errorMessageVisible,
        errorClassName,
      )}
      >
        {renderText(lang('$mnemonic_check_error'))}
      </div>

      <div className={styles.buttonWrapper}>
        <Button
          isPrimary
          isLoading={showValidation}
          isDisabled={!isAllWordsSelected}
          className={styles.footerButton}
          onClick={!showValidation ? handleContinue : undefined}
        >
          {lang('Continue')}
        </Button>
      </div>
    </>
  );
}

export default memo(CheckWordsForm);
