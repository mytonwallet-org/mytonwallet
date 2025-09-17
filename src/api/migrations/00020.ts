import { storage } from '../storages';

export async function start() {
  // Remove baseCurrency from storage as it's now handled in global state only
  try {
    await storage.removeItem('baseCurrency' as any);
  } catch {
    // The key doesn't exist
  }
}
