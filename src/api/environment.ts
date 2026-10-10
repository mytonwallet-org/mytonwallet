/*
 * This module is to be used instead of /src/util/environment.ts
 * when `window` is not available (e.g. in a web worker).
 */
import type { AgentOverride, AgentProtocolVersion } from '../util/agent/agentOverride';
import type { ApiInitArgs, ApiNetwork } from './types';

import {
  AGENT_OVERRIDE,
  ELECTRON_TONCENTER_MAINNET_KEY,
  ELECTRON_TONCENTER_TESTNET_KEY,
  IS_AIR_APP,
  IS_EXTENSION,
  TONCENTER_MAINNET_KEY,
  TONCENTER_TESTNET_KEY,
} from '../config';
import { resolveAgentProtocolVersion } from '../util/agent/agentOverride';

const ELECTRON_ORIGIN = 'file://';

export type AppEnvironment = Omit<ApiInitArgs, 'agentOverride'> & {
  agentOverride: AgentOverride;
  isAgentV2Enabled: boolean;
  isDappSupported?: boolean;
  isSseSupported?: boolean;
  apiHeaders?: AnyLiteral;
  byNetwork: Record<ApiNetwork, { toncenterKey?: string }>;
};

let environment: AppEnvironment;

export function resolveIsAgentV2Enabled(
  agentOverride: AgentOverride,
  backendVersion?: AgentProtocolVersion,
  isAndroidApp = false,
  isIosApp = false,
) {
  return isAndroidApp || isIosApp || resolveAgentProtocolVersion(agentOverride, backendVersion) === 'v2';
}

function getAppOrigin(args: ApiInitArgs): string | undefined {
  if (args.isElectron) {
    return ELECTRON_ORIGIN;
  } else if (IS_AIR_APP || IS_EXTENSION) {
    return self?.origin;
  } else {
    return undefined;
  }
}

export function setEnvironment(args: ApiInitArgs) {
  const appOrigin = getAppOrigin(args);
  const agentOverride = args.agentOverride ?? AGENT_OVERRIDE;
  environment = {
    ...args,
    agentOverride,
    isAgentV2Enabled: resolveIsAgentV2Enabled(agentOverride, undefined, args.isAndroidApp, args.isIosApp),
    isDappSupported: true,
    isSseSupported: args.isElectron || IS_AIR_APP,
    apiHeaders: appOrigin ? { 'X-App-Origin': appOrigin } : {},
    byNetwork: {
      mainnet: {
        toncenterKey: args.isElectron ? ELECTRON_TONCENTER_MAINNET_KEY : TONCENTER_MAINNET_KEY,
      },
      testnet: {
        toncenterKey: args.isElectron ? ELECTRON_TONCENTER_TESTNET_KEY : TONCENTER_TESTNET_KEY,
      },
    },
  };
  return environment;
}

export function getEnvironment() {
  return environment;
}

export function setIsAgentV2Enabled(isAgentV2Enabled: boolean) {
  environment.isAgentV2Enabled = isAgentV2Enabled;
}
