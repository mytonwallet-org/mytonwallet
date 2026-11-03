import React, { memo } from '../../lib/teact/teact';

interface OwnProps {
  body: string;
}

const BOLD_MARKER = '**';

/** A news body as its post shows it: news bodies mark emphasis with `**` and nothing else */
function AgentNewsBody({ body }: OwnProps) {
  return <>{body.split(BOLD_MARKER).map((part, index) => (index % 2 ? <strong>{part}</strong> : part))}</>;
}

export default memo(AgentNewsBody);
