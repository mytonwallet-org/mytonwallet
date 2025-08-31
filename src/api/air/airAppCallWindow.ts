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
    bridge.nativeCallCallbacks[requestNumber] = (response) => {
      delete bridge.nativeCallCallbacks[requestNumber];
      if (!response.ok) reject(new Error(ApiCommonError.Unexpected));
      else resolve(response.result as Awaited<WindowMethodResponse<T>>);
    };
    if (airWindow.webkit) {
      airWindow.webkit?.messageHandlers.nativeCall.postMessage({
        requestNumber, methodName, arg0: args[0], arg1: args[1],
      });
    } else {
      airWindow.androidApp.nativeCall(
        requestNumber, methodName, args[0], args[1],
      );
    }
  });
};
