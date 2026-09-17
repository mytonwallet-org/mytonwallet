import {
  createContext, useContextSignal, useEffect, useState,
} from '../lib/teact/teact';

import * as langProvider from '../util/langProvider';
import useEffectOnce from './useEffectOnce';
import useForceUpdate from './useForceUpdate';

export type LangFn = langProvider.LangFn;

interface LangContextValue {
  lang: LangFn;
}

const LangContext = createContext<LangContextValue | undefined>();

export const LangProvider = LangContext.Provider;

const useLang = (): LangFn => {
  const forceUpdate = useForceUpdate();
  const getContextLang = useContextSignal(LangContext);

  useEffectOnce(() => {
    return langProvider.addCallback(forceUpdate);
  });

  return getContextLang()?.lang ?? langProvider.getTranslation;
};

export function useLangForCode(langCode?: string): LangFn {
  const fallback = useLang();
  const [translation, setTranslation] = useState<{ lang: LangFn }>();
  const supportedLangCode = langCode && langProvider.isSupportedLanguageCode(langCode)
    ? langCode
    : undefined;

  useEffect(() => {
    if (!supportedLangCode || fallback.code === supportedLangCode) {
      setTranslation(undefined);
      return undefined;
    }
    let isActive = true;
    void langProvider.getTranslationForLanguage(supportedLangCode).then((nextTranslation) => {
      if (isActive) setTranslation({ lang: nextTranslation });
    });
    return () => {
      isActive = false;
    };
  }, [fallback, supportedLangCode]);

  return translation && translation.lang.code === supportedLangCode ? translation.lang : fallback;
}

export default useLang;
