import React, { memo } from '../../lib/teact/teact';

interface OwnProps {
  className?: string;
}

/** The headset that marks support in the chat, its header and the chat list */
function AgentSupportIcon({ className }: OwnProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2.4"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden
    >
      <path d="M4 14v-2a8 8 0 0 1 16 0v2" />
      <path d="M4 14h3v5H5a1 1 0 0 1-1-1Z" />
      <path d="M20 14h-3v5h2a1 1 0 0 0 1-1Z" />
    </svg>
  );
}

export default memo(AgentSupportIcon);
