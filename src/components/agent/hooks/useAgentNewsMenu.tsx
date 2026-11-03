import React, { useMemo } from '../../../lib/teact/teact';

import type { AgentThreadNewsCardV2 } from '../../../api/agentV2/protocol/types';
import type { DropdownItem } from '../../ui/Dropdown';

import { shareUrl } from '../../../util/share';
import { getAgentNewsCopyText, getAgentNewsSourceUrl, openAgentNewsSource } from '../helpers/agentNews';
import { copyAgentText } from '../helpers/copyAgentText';

import useLastCallback from '../../../hooks/useLastCallback';

import AgentOpenSourceIcon from '../AgentOpenSourceIcon';

export type AgentNewsMenuHandler = 'source' | 'copy' | 'share';

type AgentNewsMenuNews = Pick<AgentThreadNewsCardV2, 'headline' | 'body' | 'sources'>;

/**
 * The actions on a news item, as its card's and post's menu and its picture's viewer offer them: open its source when
 * it has one the app can open, copy it, and share it
 */
export default function useAgentNewsMenu(news?: AgentNewsMenuNews) {
  const sourceUrl = news && getAgentNewsSourceUrl(news);

  const menuItems = useMemo((): DropdownItem<AgentNewsMenuHandler>[] => [
    ...(sourceUrl
      ? [{ value: 'source' as const, name: '$agent_news_open_source', icon: <AgentOpenSourceIcon /> }]
      : []),
    { value: 'copy', name: 'Copy', fontIcon: 'menu-copy' },
    { value: 'share', name: 'Share', fontIcon: 'share' },
  ], [sourceUrl]);

  // Without a source to pass on, sharing passes the text
  const handleMenuItemSelect = useLastCallback((value: AgentNewsMenuHandler) => {
    if (!news) return;

    const { headline, body, sources } = news;
    switch (value) {
      case 'source':
        void openAgentNewsSource(news);
        break;
      case 'copy':
        void copyAgentText(getAgentNewsCopyText({ headline, body, sources }));
        break;
      case 'share':
        void shareUrl(sourceUrl, headline, sourceUrl ? undefined : getAgentNewsCopyText({ headline, body, sources }));
        break;
    }
  });

  return { menuItems, handleMenuItemSelect };
}
