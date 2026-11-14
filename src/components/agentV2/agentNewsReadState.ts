// When the newest news the user has seen in the MyPulse feed was delivered. It belongs to this device, as on mobile.
const READ_THROUGH_STORAGE_KEY = 'mytonwallet-agent-mypulse-read-through';

export function getAgentNewsReadThrough() {
  try {
    return localStorage.getItem(READ_THROUGH_STORAGE_KEY) ?? undefined;
  } catch {
    return undefined;
  }
}

/** Moves the mark forward to `deliveredAt`, never back, and returns the mark that holds afterwards */
export function markAgentNewsReadThrough(deliveredAt: string) {
  const readThrough = getAgentNewsReadThrough();
  if (readThrough && Date.parse(readThrough) >= Date.parse(deliveredAt)) return readThrough;

  try {
    localStorage.setItem(READ_THROUGH_STORAGE_KEY, deliveredAt);
  } catch {
    // Without storage the counter starts over on the next launch
  }
  return deliveredAt;
}

// When the newest digest the user has seen in the feed, in either view, was delivered
const DIGESTS_READ_THROUGH_STORAGE_KEY = 'mytonwallet-agent-mypulse-digests-read-through';

export function getAgentNewsDigestsReadThrough() {
  try {
    return localStorage.getItem(DIGESTS_READ_THROUGH_STORAGE_KEY) ?? undefined;
  } catch {
    return undefined;
  }
}

/** Moves the digests' mark forward to `deliveredAt`, never back, and returns the mark that holds afterwards */
export function markAgentNewsDigestsReadThrough(deliveredAt: string) {
  const readThrough = getAgentNewsDigestsReadThrough();
  if (readThrough && Date.parse(readThrough) >= Date.parse(deliveredAt)) return readThrough;

  try {
    localStorage.setItem(DIGESTS_READ_THROUGH_STORAGE_KEY, deliveredAt);
  } catch {
    // Without storage the counter starts over on the next launch
  }
  return deliveredAt;
}
