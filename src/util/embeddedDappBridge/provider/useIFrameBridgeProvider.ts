import { useEffect, useRef } from '../../../lib/teact/teact';

import { EMBEDDED_DAPP_BRIDGE_CHANNEL } from '../../../config';
import { createReverseIFrameInterface } from '../../createPostMessageInterface';
import { buildBridgeApi } from './bridgeApi';

import useLastCallback from '../../../hooks/useLastCallback';

export function useIFrameBridgeProvider(pageUrl?: string) {
  const cleanupRef = useRef<NoneToVoidFunction>();

  const setupDappBridge = useLastCallback((e) => {
    cleanupRef.current?.();

    if (!pageUrl) return;

    const iframe = e.target as HTMLIFrameElement;
    cleanupRef.current = createReverseIFrameInterface(
      buildBridgeApi(pageUrl),
      new URL(pageUrl).origin,
      iframe.contentWindow!,
      EMBEDDED_DAPP_BRIDGE_CHANNEL,
    );
  });

  useEffect(() => {
    if (!pageUrl) return;

    return () => {
      cleanupRef.current?.();
    };
  }, [pageUrl]);

  return {
    setupDappBridge,
  };
}
