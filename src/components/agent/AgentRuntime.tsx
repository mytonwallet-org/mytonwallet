import React, { memo, useEffect, useState } from '../../lib/teact/teact';

import { handleChunkLoadError } from '../../util/chunkLoading';
import { loadAgentV2Chats } from './agentV2RuntimeLoader';

import styles from './Agent.module.scss';

interface OwnProps {
  isActive: boolean;
  onScroll?: (e: React.UIEvent<HTMLDivElement>) => void;
}

type AgentV2ChatsComponent = typeof import('../agentV2/AgentV2Chats').default;

// A mount after the chats have loaded shows them at once, as when the app switches layouts across the phone breakpoint
let loadedAgentV2Chats: AgentV2ChatsComponent | undefined;

function AgentRuntime(props: OwnProps) {
  const [AgentV2Chats, setAgentV2Chats] = useState(() => loadedAgentV2Chats);

  useEffect(() => {
    if (loadedAgentV2Chats) return undefined;

    let isActive = true;
    // On a failed load the screen stays empty; mounting it again retries the load
    void loadAgentV2Chats().then((Component) => {
      loadedAgentV2Chats = Component;
      if (isActive) setAgentV2Chats(() => Component);
    }, handleChunkLoadError('AgentRuntime'));

    return () => {
      isActive = false;
    };
  }, []);

  if (!AgentV2Chats) return <div className={styles.root} />;
  return <AgentV2Chats {...props} />;
}

export default memo(AgentRuntime);
