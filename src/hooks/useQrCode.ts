import type QRCodeStyling from 'qr-code-styling';
import {
  type ElementRef,
  useEffect, useLayoutEffect, useRef, useState,
} from '../lib/teact/teact';
import { removeExtraClass } from '../lib/teact/teact-dom';

import type { ApiChain } from '../api/types';

import { IS_CORE_WALLET } from '../config';
import { getChainConfig } from '../util/chain';
import getChainNetworkIcon from '../util/swap/getChainNetworkIcon';

const QR_SIZE = 600;

interface UseQRCodeHook {
  qrCodeRef: ElementRef<HTMLDivElement>;
  isInitialized: boolean;
}

let QrCodeStylingClassConstructor: typeof QRCodeStyling | undefined;

export default function useQrCode({
  address,
  chain,
  isActive,
  hiddenClassName,
  hideLogo,
  preferUrl,
}: {
  address?: string;
  chain?: ApiChain;
  isActive?: boolean;
  hiddenClassName?: string;
  hideLogo?: boolean;
  preferUrl?: boolean;
}): UseQRCodeHook {
  const qrCodeInstanceRef = useRef<QRCodeStyling>();
  const [isInitialized, setIsInitialized] = useState(false);
  const logoUrl = IS_CORE_WALLET ? './coreWallet/logo.svg' : './logo.svg';

  const qrCodeRef = useRef<HTMLDivElement>();

  useEffect(() => {
    if (isInitialized) return;

    function createInstance(QrCodeStyling: typeof QRCodeStyling) {
      qrCodeInstanceRef.current = new QrCodeStyling({
        width: QR_SIZE,
        height: QR_SIZE,
        margin: 0,
        type: 'canvas',
        dotsOptions: { type: 'rounded' },
        cornersSquareOptions: { type: 'extra-rounded' },
        imageOptions: {
          imageSize: 0.4,
          margin: 8,
          crossOrigin: 'anonymous',
        },
        qrOptions: { errorCorrectionLevel: 'M' },
        data: '',
      });
      setIsInitialized(true);
    }

    if (QrCodeStylingClassConstructor) {
      createInstance(QrCodeStylingClassConstructor);
      return;
    }

    void import('qr-code-styling')
      .then(({ default: QrCodeStyling }) => {
        QrCodeStylingClassConstructor = QrCodeStyling;
        createInstance(QrCodeStyling);
      });
  }, [isInitialized]);

  useLayoutEffect(() => {
    const qrCode = qrCodeInstanceRef.current;
    if (!isActive || !isInitialized || !qrCode || !qrCodeRef.current) return;

    if (hiddenClassName) removeExtraClass(qrCodeRef.current, hiddenClassName);

    if (!qrCodeRef.current.hasChildNodes()) {
      qrCode.append(qrCodeRef.current);
    }

    const image = hideLogo ? undefined : (chain ? getChainNetworkIcon(chain) : logoUrl);
    const formatTransferUrl = chain && getChainConfig(chain).formatTransferUrl;
    const data = address && preferUrl && formatTransferUrl ? formatTransferUrl(address) : (address || '');

    qrCode.update({ data, image });
  }, [isActive, isInitialized, hiddenClassName, address, chain, hideLogo, logoUrl, preferUrl]);

  return { qrCodeRef, isInitialized };
}
