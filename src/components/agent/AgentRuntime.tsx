import React, { memo, useEffect, useState } from '../../lib/teact/teact';

import { handleChunkLoadError } from '../../util/chunkLoading';
import { loadAgentV2Classic } from './agentV2RuntimeLoader';
import useAgentProtocolVersion from './useAgentProtocolVersion';

import Agent from './Agent';

import styles from './Agent.module.scss';

interface OwnProps {
  isActive: boolean;
  onScroll?: (e: React.UIEvent<HTMLDivElement>) => void;
}

function AgentRuntime(props: OwnProps) {
  const agentProtocolVersion = useAgentProtocolVersion();
  if (agentProtocolVersion === 'v1') {
    return <Agent {...props} />;
  }

  return <AgentV2Runtime {...props} />;
}

function AgentV2Runtime(props: OwnProps) {
  const [AgentV2Classic, setAgentV2Classic] = useState<typeof import('../agentV2/AgentV2Classic').default>();

  useEffect(() => {
    let isActive = true;
    // On a failed load the screen stays empty; mounting it again retries the load
    void loadAgentV2Classic().then((Component) => {
      if (isActive) setAgentV2Classic(() => Component);
    }, handleChunkLoadError('AgentRuntime'));

    return () => {
      isActive = false;
    };
  }, []);

  if (!AgentV2Classic) return <div className={styles.root} />;
  return <AgentV2Classic {...props} />;
}

export default memo(AgentRuntime);
