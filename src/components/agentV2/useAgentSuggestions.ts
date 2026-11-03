import { useEffect, useMemo, useState } from '../../lib/teact/teact';

import type { AgentStarterHintIdV2 } from '../../api/agentV2/protocol/types';
import type { AgentHint, LangCode } from '../../global/types';
import type { LangFn } from '../../util/langProvider';

import { callApi } from '../../api';
import { getAgentV2HintCopy } from './agentV2Copy';

// The suggestions of a language are kept this long, as on mobile
const CACHE_DURATION = 10 * 60 * 1000;
const MAX_SUGGESTIONS = 5;

let cache: { langCode: LangCode; ids: AgentStarterHintIdV2[]; loadedAt: number } | undefined;

/**
 * The questions suggested for a new chat while the user composes one under the chat list. They are loaded while
 * `isEnabled`, and again as `shouldRefresh` turns on once they are out of date.
 */
export default function useAgentSuggestions(lang: LangFn, isEnabled: boolean, shouldRefresh: boolean) {
  const langCode = lang.code ?? 'en';
  const [ids, setIds] = useState(() => getCachedIds(langCode));

  useEffect(() => {
    if (!isEnabled) return undefined;

    const cachedIds = getCachedIds(langCode);
    if (cachedIds) {
      setIds(cachedIds);
      return undefined;
    }

    let isCurrent = true;
    void callApi('getAgentV2Hints', langCode).then((response) => {
      // A failed load keeps the suggestions shown
      if (!response) return;

      const loadedIds = response.items.slice(0, MAX_SUGGESTIONS).map(({ id }) => id);
      cache = { langCode, ids: loadedIds, loadedAt: Date.now() };
      if (isCurrent) setIds(loadedIds);
    }).catch(() => undefined);

    return () => {
      isCurrent = false;
    };
  }, [isEnabled, langCode, shouldRefresh]);

  return useMemo<AgentHint[] | undefined>(() => ids?.map((id) => ({
    id, langCode, ...getAgentV2HintCopy(id, lang),
  })), [ids, lang, langCode]);
}

function getCachedIds(langCode: LangCode) {
  return cache?.langCode === langCode && Date.now() - cache.loadedAt < CACHE_DURATION ? cache.ids : undefined;
}
