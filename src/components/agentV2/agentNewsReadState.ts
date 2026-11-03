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
