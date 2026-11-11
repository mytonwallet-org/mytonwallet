import type { WindowMethodArgs, WindowMethodResponse, WindowMethods } from '../../util/windowProvider/types';
import type { AirWindow } from '../types/air';
import { ApiCommonError } from '../types';

let nativeCallNumber = 0;

export const airAppCallWindow = <T extends keyof WindowMethods>(methodName: T, ...args: WindowMethodArgs<T>) => {
  const airWindow = window as AirWindow;
  const bridge = airWindow.airBridge;
  return new Promise<Awaited<WindowMethodResponse<T>>>((resolve, reject) => {
    nativeCallNumber++;
    const requestNumber = nativeCallNumber;
    const hasDeadline = methodName.startsWith('airInstallation');
    const timeout = hasDeadline ? setTimeout(() => {
      delete bridge.nativeCallCallbacks[requestNumber];
      reject(new Error('Installation service timed out'));
    }, 5000) : undefined;
    bridge.nativeCallCallbacks[requestNumber] = (response) => {
      clearTimeout(timeout);
      delete bridge.nativeCallCallbacks[requestNumber];
      if (!response.ok) reject(new Error(ApiCommonError.Unexpected));
      else resolve(response.result as Awaited<WindowMethodResponse<T>>);
    };
    try {
      if (airWindow.webkit) {
        airWindow.webkit?.messageHandlers.nativeCall.postMessage({
          requestNumber, methodName, arg0: args[0], arg1: args[1],
        });
      } else {
        const [arg0, arg1] = args;
        // eslint-disable-next-line no-null/no-null -- The Java bridge turns `undefined` into the string "undefined"
        airWindow.androidApp!.nativeCall(requestNumber, methodName, arg0 ?? null, arg1 ?? null);
      }
    } catch (error) {
      clearTimeout(timeout);
      delete bridge.nativeCallCallbacks[requestNumber];
      reject(error);
    }
  });
};
