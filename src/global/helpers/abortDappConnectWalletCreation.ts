let isAbortRequested = false;

export function requestAbortDappConnectWalletCreation() {
  isAbortRequested = true;
}

export function peekAbortDappConnectWalletCreation() {
  return isAbortRequested;
}

export function clearAbortDappConnectWalletCreation() {
  isAbortRequested = false;
}

/** Returns true if an abort was requested and clears the flag. */
export function takeAbortDappConnectWalletCreationIfRequested() {
  if (!isAbortRequested) {
    return false;
  }
  isAbortRequested = false;
  return true;
}
