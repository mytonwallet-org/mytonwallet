import type { bigintReviver } from '../../util/bigint';
import type { WindowMethodResponse, WindowMethods } from '../../util/windowProvider/types';
import type { callApi, handleInstallationStateChange, initApi } from '../providers/direct/connector';

type NativeCallbackResponse =
  | { ok: false }
  | { ok: true; result: Awaited<WindowMethodResponse<keyof WindowMethods>> };

interface AirBridge {
  initApi: typeof initApi;
  callApi: typeof callApi;
  handleInstallationStateChange: typeof handleInstallationStateChange;
  bigintReviver: typeof bigintReviver;
  nativeCallCallbacks: Record<number, (response: NativeCallbackResponse) => void>;
}

interface AndroidAppBridge {
  nativeCall(requestNumber: number, methodName: string, arg0?: unknown, arg1?: unknown): void;
}

export type AirWindow = Window & typeof globalThis & {
  airBridge: AirBridge;
  webkit?: any;
  androidApp?: AndroidAppBridge;
};
