import type { bigintReviver } from '../../util/bigint';
import type { WindowMethodResponse, WindowMethods } from '../../util/windowProvider/types';
import type { callApi, captureInstallAttribution, initApi, setInstallChannel } from '../providers/direct/connector';

type NativeCallbackResponse =
  | { ok: false }
  | { ok: true; result: Awaited<WindowMethodResponse<keyof WindowMethods>> };

interface AirBridge {
  initApi: typeof initApi;
  callApi: typeof callApi;
  setInstallChannel: typeof setInstallChannel;
  captureInstallAttribution: typeof captureInstallAttribution;
  bigintReviver: typeof bigintReviver;
  nativeCallCallbacks: Record<number, (response: NativeCallbackResponse) => void>;
}

export type AirWindow = Window & typeof globalThis & { airBridge: AirBridge; webkit?: any; androidApp?: any };
