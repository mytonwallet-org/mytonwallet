export interface ApiRuntimeProfile {
  shouldInstallWindowBridge: boolean;
  shouldInitDappRuntime: boolean;
}

export const browserApiRuntime: ApiRuntimeProfile = {
  shouldInstallWindowBridge: true,
  shouldInitDappRuntime: true,
};

export const nodeApiRuntime: ApiRuntimeProfile = {
  shouldInstallWindowBridge: false,
  shouldInitDappRuntime: false,
};
