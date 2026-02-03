import React, { memo, useEffect, useRef, useState } from '../../lib/teact/teact';

import { PRIVATE_KEY_HEX_LENGTH } from '../../config';
import { requestMeasure } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { callApi } from '../../api';

import useFlag from '../../hooks/useFlag';
import useKeyboardListNavigation from '../../hooks/useKeyboardListNavigation';
import useLastCallback from '../../hooks/useLastCallback';
import useSuggestionsPosition from '../ui/hooks/useSuggestionsPosition';

import SuggestionList, { SUGGESTION_ITEM_CLASS_NAME } from '../ui/SuggestionList';

import styles from './InputMnemonic.module.scss';

type OwnProps = {
  id?: string;
  nextId?: string;
  labelText?: string;
  className?: string;
  value?: string;
  inputArg?: any;
  onInput: (value: string, inputArg?: any) => void;
  onEnter?: NoneToVoidFunction;
};

const SUGGESTION_WORDS_COUNT = 5;

function InputMnemonic({
  id, nextId, labelText, className, value = '', inputArg, onInput, onEnter,
}: OwnProps) {
  const wrapperRef = useRef<HTMLDivElement>();

  const [hasFocus, markFocus, unmarkFocus] = useFlag();
  const [hasError, setHasError] = useState<boolean>(false);
  const [filteredSuggestions, setFilteredSuggestions] = useState<string[]>([]);
  const [areSuggestionsShown, setAreSuggestionsShown] = useState<boolean>(false);
  const [wordlist, setWordlist] = useState<string[]>([]);
  const shouldRenderSuggestions = Boolean(areSuggestionsShown && value && filteredSuggestions.length > 0);

  useEffect(() => {
    void callApi('getMnemonicWordList').then((words) => setWordlist(words ?? []));
  }, []);

  const handleSelectWithEnter = useLastCallback((index: number) => {
    const suggestedValue = filteredSuggestions[index];
    if (!suggestedValue) return;

    onInput(suggestedValue, inputArg);
    setFilteredSuggestions([suggestedValue]);
    setAreSuggestionsShown(false);

    if (nextId) {
      requestMeasure(() => {
        requestMeasure(() => {
          const nextInput = document.getElementById(nextId);
          nextInput?.focus();
          (nextInput as HTMLInputElement)?.select();
        });
      });
    }
  });

  const {
    activeIndex,
    listRef: suggestionsRef,
    handleKeyDown: handleKeyDownNavigation,
    resetIndex,
  } = useKeyboardListNavigation(
    shouldRenderSuggestions,
    handleSelectWithEnter,
    `.${SUGGESTION_ITEM_CLASS_NAME}`,
  );

  const { position: suggestionsPosition, isPositionReady } = useSuggestionsPosition(
    wrapperRef,
    suggestionsRef,
    filteredSuggestions.length,
    shouldRenderSuggestions,
  );

  useEffect(() => {
    const noError = !value
      || (areSuggestionsShown && filteredSuggestions.length > 0)
      || isCorrectMnemonic(value, wordlist);
    setHasError(!noError);
  }, [areSuggestionsShown, filteredSuggestions.length, value, wordlist]);

  const processSuggestions = (userInput: string) => {
    // Filter our suggestions that don't contain the user's input
    const unLinked = wordlist.filter(
      (suggestion) => suggestion.toLowerCase().startsWith(userInput.toLowerCase()),
    ).slice(0, SUGGESTION_WORDS_COUNT);

    onInput(userInput, inputArg);
    setFilteredSuggestions(unLinked);
    setAreSuggestionsShown(true);
    resetIndex();
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const userInput = e.target.value;

    processSuggestions(userInput);
  };

  const handlePaste = (e: React.ClipboardEvent<HTMLInputElement>) => {
    const pastedValue = e.clipboardData.getData('text');

    if (!pastedValue) return;

    processSuggestions(pastedValue);
  };

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLInputElement>) => {
    // Call `onEnter` when Enter button is pressed without suggestions
    if (e.key === 'Enter' && !shouldRenderSuggestions && onEnter) {
      onEnter();
      return;
    }

    handleKeyDownNavigation(e);
  });

  // Handle Tab key separately for Enter-like behavior
  useEffect(() => {
    if (!hasFocus || !shouldRenderSuggestions) return undefined;

    return captureKeyboardListeners({
      onTab: (e: KeyboardEvent) => {
        if (!(e.shiftKey || e.ctrlKey || e.altKey || e.metaKey)) {
          e.preventDefault();

          // If nothing is selected (activeIndex < 0), select the first item
          const indexToSelect = activeIndex < 0 ? 0 : activeIndex;
          handleSelectWithEnter(indexToSelect);
        }
      },
    });
  }, [hasFocus, shouldRenderSuggestions, activeIndex, handleSelectWithEnter]);

  const handleClick = useLastCallback((suggestion: string) => {
    onInput(suggestion, inputArg);
    setAreSuggestionsShown(false);
    setFilteredSuggestions([]);
    resetIndex();

    if (nextId) {
      // During the first render, the value is set.
      // During the second render, the component is re-rendered and ready for focus.
      requestMeasure(() => {
        requestMeasure(() => {
          const nextInput = document.getElementById(nextId);
          nextInput?.focus();
          (nextInput as HTMLInputElement)?.select();
        });
      });
    }
  });

  const handleFocus = (e: React.FocusEvent<HTMLInputElement>) => {
    processSuggestions(e.target.value);
    markFocus();
  };

  const handleBlur = (e: React.FocusEvent<HTMLInputElement>) => {
    // Remove focus from the input element to ensure correct blur handling, especially when triggered by window switching
    e.target.blur();

    unmarkFocus();
    requestAnimationFrame(() => {
      setAreSuggestionsShown(false);
      setFilteredSuggestions([]);
    });
  };

  return (
    <div
      ref={wrapperRef}
      className={buildClassName(
        styles.wrapper,
        className,
        hasFocus && styles.wrapper_focus,
        hasError && styles.wrapper_error,
      )}
    >
      {shouldRenderSuggestions && (
        <SuggestionList
          listRef={suggestionsRef}
          suggestions={filteredSuggestions}
          activeIndex={activeIndex}
          position={suggestionsPosition}
          isHidden={!isPositionReady}
          onSelect={handleClick}
        />
      )}
      <label className={styles.label} htmlFor={id}>{labelText}.</label>
      <input
        id={id}
        className={buildClassName(styles.input, value !== '' && styles.touched)}
        type="text"
        autoCapitalize="none"
        autoComplete="off"
        autoCorrect={false}
        spellCheck={false}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        onFocus={handleFocus}
        onBlur={handleBlur}
        onPaste={handlePaste}
        value={value}
        tabIndex={0}
        data-focus-scroll-position={suggestionsPosition === 'top' ? 'end' : 'start'}
      />
    </div>
  );
}

function isCorrectMnemonic(mnemonic: string, wordlist: string[]) {
  return mnemonic.length === PRIVATE_KEY_HEX_LENGTH || wordlist.includes(mnemonic.toLowerCase());
}

export default memo(InputMnemonic);
