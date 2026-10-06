import type { AirWindow } from '../types/air';

import { AGENT_API_URL, APP_VERSION, SDK_BUILD_STAMP } from '../../config';
import { bigintReviver } from '../../util/bigint';
import { installFetchLogging } from '../../util/fetchLogging';
import contractManifest from '../agentV2/generated/manifest.json';
import { callApi, captureInstallAttribution, initApi, setInstallChannel } from '../providers/direct/connector';

export const airWindow = window as AirWindow;

// The native side captures `console.log` and writes it to the log the diagnostics export ships,
// so this is the channel that reaches a user's report; the wrapper goes on before anything else
// here so no request the SDK makes escapes it.
// eslint-disable-next-line no-console
installFetchLogging(window, (line) => console.log(line));

/**
 * The first line the native log gets, written as the bundle loads.
 *
 * The native app and the JS bundle inside it are versioned and shipped separately, and the app
 * reports only its own numbers, so an installed build was found running a bundle six weeks older
 * than the wrapper around it with nothing anywhere able to state that. The Agent host and the
 * protocol are in the same position: both are fixed at build time and a running app had no way to
 * name either, which turned a chat refusing to open into an afternoon of inference from request
 * headers. None of the four values is user data.
 */
// eslint-disable-next-line no-console
console.log(
  `sdk build=${SDK_BUILD_STAMP} app=${APP_VERSION} agent=${agentOrigin()} protocol=${contractManifest.protocolVersion}`,
);

function agentOrigin() {
  try {
    return new URL(AGENT_API_URL).origin;
  } catch {
    // A host that does not parse is the case most worth seeing, so print it as configured.
    return AGENT_API_URL;
  }
}

airWindow.airBridge = {
  initApi,
  callApi,
  setInstallChannel,
  captureInstallAttribution,
  bigintReviver,
  nativeCallCallbacks: {},
};
