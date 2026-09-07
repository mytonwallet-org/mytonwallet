import type { AirWindow } from '../types/air';

import { bigintReviver } from '../../util/bigint';
import { callApi, captureInstallAttribution, initApi, setInstallChannel } from '../providers/direct/connector';

export const airWindow = window as AirWindow;

airWindow.airBridge = {
  initApi,
  callApi,
  setInstallChannel,
  captureInstallAttribution,
  bigintReviver,
  nativeCallCallbacks: {},
};
