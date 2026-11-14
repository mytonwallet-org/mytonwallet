import React, { useMemo } from '../../../lib/teact/teact';

import type { AgentNewsFeedLocaleV2, AgentThreadNewsCardV2 } from '../../../api/agentV2/protocol/types';
import type { DropdownItem } from '../../ui/Dropdown';

import { getAgentNewsFeedLocale } from '../../../util/agent/agentNewsFeedLocale';
import { openUrl } from '../../../util/openUrl';
import { shareUrl } from '../../../util/share';
import { getAgentNewsShareUrl } from '../../../util/url';
import { IS_IOS } from '../../../util/windowEnvironment';
import { getAgentNewsCopyText, getAgentNewsMenuSources } from '../helpers/agentNews';
import { copyAgentText } from '../helpers/copyAgentText';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import AgentOpenSourceIcon from '../AgentOpenSourceIcon';

export type AgentNewsMenuHandler = 'sources' | 'back' | 'copy' | 'share' | `source-${number}`;

/** A news item has its `eventId`, which its link names; a digest has none, and no Share */
type AgentNewsMenuNews = Pick<AgentThreadNewsCardV2, 'headline' | 'body' | 'sources'> & { eventId?: number };

const COPY_ITEM: DropdownItem<AgentNewsMenuHandler> = { value: 'copy', name: 'Copy', fontIcon: 'menu-copy' };
const SHARE_ITEM: DropdownItem<AgentNewsMenuHandler> = {
  value: 'share', name: 'Share', fontIcon: IS_IOS ? 'share-ios' : 'share-android',
};

/**
 * The actions on a news item, as its card's and post's menu and its picture's viewer offer them: its sources, Copy,
 * which copies its text, and Share, which sends its headline and link. The link names `locale`, the language the news
 * is shown in, or the feed's language for the app's when it is not known. In the menu, Sources opens a page of the
 * sources the app can open, each opening its link, with Back to the actions; `resetMenu` returns it to them as it
 * closes. The viewer's buttons, `actionItems`, open `sourceItems` from Sources in a menu of their own.
 */
export default function useAgentNewsMenu(news?: AgentNewsMenuNews, locale?: AgentNewsFeedLocaleV2) {
  const lang = useLang();
  const hasShare = news?.eventId !== undefined;
  const menuSources = useMemo(() => (news ? getAgentNewsMenuSources(news) : []), [news]);
  const [isSourcesPageOpen, openSourcesPage, closeSourcesPage] = useFlag();

  const sourceItems = useMemo((): DropdownItem<AgentNewsMenuHandler>[] => menuSources.map(({ name }, index) => ({
    value: `source-${index}` as const, name, noTranslate: true,
  })), [menuSources]);

  const actionItems = useMemo((): DropdownItem<AgentNewsMenuHandler>[] => [
    ...(menuSources.length
      ? [{ value: 'sources' as const, name: '$agent_news_sources', icon: <AgentOpenSourceIcon /> }]
      : []),
    COPY_ITEM,
    ...(hasShare ? [SHARE_ITEM] : []),
  ], [hasShare, menuSources]);

  const menuItems = useMemo((): DropdownItem<AgentNewsMenuHandler>[] => {
    if (isSourcesPageOpen) {
      return [
        { value: 'back', name: 'Back', fontIcon: 'chevron-left', shouldKeepOpen: true, withDelimiterAfter: true },
        ...sourceItems,
      ];
    }

    // With a pointer, Sources opens the sources in a menu beside it; on a touch screen it shows them in its place
    return [
      ...(menuSources.length
        ? [{
          value: 'sources' as const,
          name: '$agent_news_sources',
          icon: <AgentOpenSourceIcon />,
          shouldKeepOpen: true,
          subItems: sourceItems,
        }]
        : []),
      COPY_ITEM,
      ...(hasShare ? [SHARE_ITEM] : []),
    ];
  }, [hasShare, isSourcesPageOpen, menuSources, sourceItems]);

  const handleMenuItemSelect = useLastCallback((value: AgentNewsMenuHandler) => {
    if (!news) return;

    const { headline, body, eventId } = news;
    switch (value) {
      case 'sources':
        openSourcesPage();
        break;
      case 'back':
        closeSourcesPage();
        break;
      case 'copy':
        void copyAgentText(getAgentNewsCopyText({ headline, body }));
        break;
      case 'share': {
        const url = getAgentNewsShareUrl(eventId!, locale ?? getAgentNewsFeedLocale(lang.code ?? 'en'));
        // Messengers take the shared text, not the title, with the link
        void shareUrl(url, headline, headline);
        break;
      }
      default: {
        const source = menuSources[Number(value.slice('source-'.length))];
        if (source) void openUrl(source.url);
      }
    }
  });

  return {
    menuItems, actionItems, sourceItems, handleMenuItemSelect, resetMenu: closeSourcesPage,
  };
}
