import { MULTISEND_DAPP_URL } from '../config';
import { getTranslation } from './langProvider';
import { openUrl } from './openUrl';
import { getHostnameFromUrl } from './url';

export function openMultisend() {
  return openUrl(MULTISEND_DAPP_URL, {
    title: getTranslation('Multisend'),
    subtitle: getHostnameFromUrl(MULTISEND_DAPP_URL),
  });
}
