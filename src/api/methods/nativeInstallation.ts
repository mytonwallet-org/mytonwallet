import { callWindow } from '../../util/windowProvider/connector';
import { postInstallationEvent } from '../common/installationDelivery';

export async function reportNativeInstallation(isAlive: () => boolean = () => true): Promise<boolean> {
  try {
    const pending = await callNativeWhileOwned(() => callWindow('airInstallationGetPending'), isAlive);
    const acknowledged = await Promise.all(pending.map(async (delivery) => {
      if (!isAlive()) return false;
      try {
        const response = await postInstallationEvent(delivery.body);
        if (!isAlive()) return false;
        const acknowledgement = JSON.stringify(response);
        if (acknowledgement === undefined) return false;
        return await callNativeWhileOwned(() => callWindow(
          'airInstallationAcknowledge', delivery.slot, acknowledgement,
        ), isAlive);
      } catch {
        return false;
      }
    }));
    return acknowledged.every((isAcknowledged) => isAcknowledged);
  } catch {
    return false;
  }
}

async function callNativeWhileOwned<T>(operation: () => T | Promise<T>, isAlive: () => boolean) {
  if (!isAlive()) throw new Error('SDK owner was replaced');
  const result = await operation();
  if (!isAlive()) throw new Error('SDK owner was replaced');
  return result;
}
