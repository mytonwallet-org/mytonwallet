import { createCallbackManager } from '../../util/callbacks';

/** The minutes the digest can come at, as the server sends it each quarter of an hour */
export const AGENT_DIGEST_MINUTES = [0, 15, 30, 45] as const;

export type AgentDigestMinute = typeof AGENT_DIGEST_MINUTES[number];

export interface AgentDigestTime {
  hour: number;
  minute: AgentDigestMinute;
}

// The hour and the minute share one key, so another tab never reads one without the other
const TIME_STORAGE_KEY = 'mytonwallet-agent-mypulse-digest-time';
const HOUR_STORAGE_KEY = 'mytonwallet-agent-mypulse-digest-hour';
const DEFAULT_TIME: AgentDigestTime = { hour: 21, minute: 0 };
const timeChanges = createCallbackManager<(time: AgentDigestTime) => void>();
// The object stays the same until the time changes, so it can be compared and kept in state
let fallbackTime = DEFAULT_TIME;
let hasWriteFailed = false;

export function setAgentDigestTime({ hour, minute }: AgentDigestTime) {
  if (!isDigestHour(hour) || !isDigestMinute(minute)) throw new RangeError('Invalid digest time');
  const previousTime = getAgentDigestTime();
  const isUnchanged = hour === previousTime.hour && minute === previousTime.minute;
  // A time whose write failed is written again when picked again, without telling anyone of it twice
  if (isUnchanged && !hasWriteFailed) return;
  if (!isUnchanged) fallbackTime = { hour, minute };

  try {
    localStorage.setItem(TIME_STORAGE_KEY, JSON.stringify(fallbackTime));
    hasWriteFailed = false;
  } catch {
    hasWriteFailed = true;
  }
  if (!isUnchanged) timeChanges.runCallbacks(fallbackTime);
}

export function subscribeToAgentDigestTime(callback: (time: AgentDigestTime) => void) {
  const unsubscribe = timeChanges.addCallback(callback);
  function handleStorage(e: StorageEvent) {
    if (e.storageArea === localStorage && (!e.key || e.key === TIME_STORAGE_KEY || e.key === HOUR_STORAGE_KEY)) {
      // Another tab's write is newer than a time this tab could not store
      hasWriteFailed = false;
      callback(getAgentDigestTime());
    }
  }
  window.addEventListener('storage', handleStorage);
  return () => {
    unsubscribe();
    window.removeEventListener('storage', handleStorage);
  };
}

export function getAgentDigestTime(): AgentDigestTime {
  if (hasWriteFailed) return fallbackTime;
  try {
    const time = readStoredTime();
    if (time && (time.hour !== fallbackTime.hour || time.minute !== fallbackTime.minute)) fallbackTime = time;
  } catch {
    // The last selection survives remounts while storage is unavailable
  }
  return fallbackTime;
}

// Nothing stored keeps the last selection
function readStoredTime(): AgentDigestTime | undefined {
  const storedTime = localStorage.getItem(TIME_STORAGE_KEY) ?? undefined;
  if (storedTime !== undefined) {
    const time: unknown = JSON.parse(storedTime);
    return isDigestTime(time) ? { hour: time.hour, minute: time.minute } : DEFAULT_TIME;
  }

  // An hour stored without a time comes on the hour
  const storedHour = localStorage.getItem(HOUR_STORAGE_KEY) ?? undefined;
  if (storedHour === undefined) return undefined;
  const hour: unknown = JSON.parse(storedHour);
  return isDigestHour(hour) ? { hour, minute: 0 } : DEFAULT_TIME;
}

function isDigestTime(value: unknown): value is AgentDigestTime {
  return typeof value === 'object' && Boolean(value) && 'hour' in value && 'minute' in value
    && isDigestHour(value.hour) && isDigestMinute(value.minute);
}

function isDigestHour(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 23;
}

function isDigestMinute(value: unknown): value is AgentDigestMinute {
  return AGENT_DIGEST_MINUTES.some((minute) => minute === value);
}
