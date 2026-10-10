import { SELF_PROTOCOL } from '../deeplink/constants';

const UNSAFE_URL_CHARACTERS = /[\s\\\p{Cc}]/u;
/** The deeplink commands that only open a screen of the app, a settings section included */
const APP_SCREEN_PATH = /^(?:explore|market|portfolio|multisend|settings(?:\/[a-z][a-z0-9-]*)?)$/u;

/**
 * Whether the app may open `value` from agent answer text: an `https` URL with a host and no credentials, or a
 * deeplink of this app to one of its screens, which the deeplink handler opens
 */
export function isAgentLinkUrl(value: string): boolean {
  if (UNSAFE_URL_CHARACTERS.test(value)) return false;
  if (value.startsWith(SELF_PROTOCOL)) return APP_SCREEN_PATH.test(value.slice(SELF_PROTOCOL.length));
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && Boolean(url.hostname) && !url.username && !url.password;
  } catch {
    return false;
  }
}
