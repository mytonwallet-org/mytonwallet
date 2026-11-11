import { createCallbackManager } from '../../util/callbacks';

const STORAGE_KEY = 'mytonwallet-agent-mypulse-digest-hour';
const DEFAULT_HOUR = 21;
const hourChanges = createCallbackManager<(hour: number) => void>();
let fallbackHour = DEFAULT_HOUR;
let hasWriteFailed = false;

export function setAgentDigestHour(hour: number) {
  if (!Number.isInteger(hour) || hour < 0 || hour > 23) throw new RangeError('Invalid digest hour');
  const previousHour = getAgentDigestHour();
  fallbackHour = hour;
  if (hour === previousHour) return;

  try {
    localStorage.setItem(STORAGE_KEY, String(hour));
    hasWriteFailed = false;
  } catch {
    hasWriteFailed = true;
  }
  hourChanges.runCallbacks(hour);
}

export function subscribeToAgentDigestHour(callback: (hour: number) => void) {
  const unsubscribe = hourChanges.addCallback(callback);
  function handleStorage(event: StorageEvent) {
    if (event.storageArea === localStorage && (!event.key || event.key === STORAGE_KEY)) {
      callback(getAgentDigestHour());
    }
  }
  window.addEventListener('storage', handleStorage);
  return () => {
    unsubscribe();
    window.removeEventListener('storage', handleStorage);
  };
}

export function getAgentDigestHour(): number {
  if (hasWriteFailed) return fallbackHour;
  try {
    const hour: unknown = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? String(fallbackHour));
    fallbackHour = typeof hour === 'number' && Number.isInteger(hour) && hour >= 0 && hour <= 23 ? hour : DEFAULT_HOUR;
  } catch {
    // The last selection survives remounts while storage is unavailable
  }
  return fallbackHour;
}
