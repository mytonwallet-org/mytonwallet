let initialization: Promise<void> | undefined;

// One subscription for the application lifetime, independent of mounted screens.
export function initAgentV2HostContext() {
  initialization ||= import('./agentV2/hostContextSync')
    .then(({ startAgentV2HostContextSync }) => {
      startAgentV2HostContextSync();
    });
  return initialization;
}
