import React, { memo, useMemo } from '../../lib/teact/teact';

import type { TabWithProperties } from '../ui/TabList';
import type { AgentNewsFeedView } from './agentNewsFeedView';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TabList from '../ui/TabList';

import styles from './AgentNewsViewSwitch.module.scss';

interface OwnProps {
  view: AgentNewsFeedView;
  onChange: (view: AgentNewsFeedView) => void;
}

const VIEWS: AgentNewsFeedView[] = ['all', 'digests'];

/**
 * The News thread's "All News | Digests" switch in the header, in the title's place: the app's tabs on a glass capsule,
 * sized by their titles, as on iOS
 */
function AgentNewsViewSwitch({ view, onChange }: OwnProps) {
  const lang = useLang();
  const tabs = useMemo<TabWithProperties[]>(() => [
    { id: 0, title: lang('$agent_news_view_all') },
    { id: 1, title: lang('$agent_news_view_digests') },
  ], [lang]);

  const handleSwitchTab = useLastCallback((index: number) => {
    onChange(VIEWS[index]);
  });

  return (
    <div className={styles.root} data-agent-news-view-switch>
      <TabList
        tabs={tabs}
        activeTab={VIEWS.indexOf(view)}
        className={styles.tabs}
        overlayClassName={styles.tabsOverlay}
        onSwitchTab={handleSwitchTab}
      />
    </div>
  );
}

export default memo(AgentNewsViewSwitch);
