import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import { loadAgentV2Chats } from './agentV2RuntimeLoader';

import useChunk from '../../hooks/useChunk';

import styles from './Agent.module.scss';

interface OwnProps {
  isActive: boolean;
  onScroll?: (e: React.UIEvent<HTMLDivElement>) => void;
}

function AgentRuntime(props: OwnProps) {
  const AgentV2Chats = useChunk(loadAgentV2Chats, true);

  // The root stays the same when the chats arrive, because `Transition` plays the screen change on this element
  return (
    <div className={buildClassName(styles.root, styles.runtimeRoot)}>
      {AgentV2Chats && <AgentV2Chats {...props} />}
    </div>
  );
}

export default memo(AgentRuntime);
