import { getActions, getGlobal } from '../global';

import { SUBPROJECT_URL_MASK } from '../config';
import { closeAllOverlays } from '../global/helpers/misc';
import { selectCurrentAccount } from '../global/selectors';
import { isInIframeWhitelist, isTelegramUrl, safeParseUrl } from './url';
import { IS_ELECTRON } from './windowEnvironment';

const [, SUBPROJECT_HOST_ENDING] = SUBPROJECT_URL_MASK.split('*');
// Desktop shells pass every `window.open` URL to the system, which opens other schemes with local programs
const ELECTRON_EXTERNAL_URL_PROTOCOLS = new Set(['http:', 'https:', 'mailto:']);

export type OpenUrlOptions = {
  isExternal?: boolean;
  title?: string;
  subtitle?: string;
  shouldSkipOverlayClose?: boolean;
};

export async function openUrl(url: string, options?: OpenUrlOptions) {
  if (isSubproject(url)) {
    url = `${url}#${buildSubprojectContext()}`;
  }

  if (
    !options?.isExternal
    && url.startsWith('http')
    && (isSubproject(url) || isInIframeWhitelist(url))
    && !isTelegramUrl(url)
  ) {
    if (!options?.shouldSkipOverlayClose) {
      await closeAllOverlays();
    }

    getActions().openBrowser({
      url,
      title: options?.title,
      subtitle: options?.subtitle,
    });
  } else {
    if (IS_ELECTRON && !ELECTRON_EXTERNAL_URL_PROTOCOLS.has(safeParseUrl(url)?.protocol ?? '')) {
      return;
    }

    window.open(url, '_blank', 'noopener');
  }
}

function buildSubprojectContext() {
  const global = getGlobal();
  const { theme, langCode, baseCurrency } = global.settings;
  const account = selectCurrentAccount(global);

  const addresses = Object.entries(account?.byChain ?? {})
    .map(([chain, wallet]) => (wallet?.address ? `${chain}:${wallet.address}` : undefined))
    .filter(Boolean)
    .join(',');

  return new URLSearchParams({
    theme,
    lang: langCode,
    baseCurrency,
    ...(addresses && { addresses }),
  });
}

export function isSubproject(url: string) {
  const { host } = new URL(url);
  return host.endsWith(SUBPROJECT_HOST_ENDING) || host.startsWith('localhost:432');
}

export function handleUrlClick(
  e: React.MouseEvent<HTMLAnchorElement, MouseEvent>,
  options?: OpenUrlOptions,
) {
  e.preventDefault();
  void openUrl(e.currentTarget.href, {
    ...options,
    isExternal: e.shiftKey || e.ctrlKey || e.metaKey,
  });
}
