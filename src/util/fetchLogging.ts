/**
 * One log line per request the SDK makes, written once the outcome is known.
 *
 * The line exists because a chat that would not open said nothing about itself: the server was
 * answering 426 on a host the bundle never named, and establishing that took a device log export,
 * an ingress access log and a throwaway pod echoing request headers back. It lives here rather
 * than in the native bridge that used to carry a switched-off copy of it, because the same SDK
 * runs on both mobile platforms and because a redaction rule is a security boundary that has to be
 * testable.
 *
 * What is kept is the method, the origin, a redacted path, the status and the duration. The body
 * and the query string never appear, and the path survives only segment by segment: a route like
 * `/staking/state/<address>` carries a wallet address in the path itself. That leaves
 * `/api/v2/device-token` readable and drops addresses, ids and tokens.
 */

/**
 * A segment is kept only when it is shaped like a route word - letters and hyphens, or a version
 * such as `v2`. Judging by length and character class instead keeps short identifiers, and a short
 * identifier is as user-linked as a long one: `/swap/history/<address>/2545651` names a swap.
 */
const ROUTE_SEGMENT = /^(?:[A-Za-z][A-Za-z-]{0,23}|v\d{1,3})$/u;
const REDACTED_SEGMENT = '<redacted>';
const UNPARSED_TARGET = '<unparsed>';

export function redactPath(pathname: string): string {
  return pathname
    .split('/')
    .map((segment) => (segment === '' || ROUTE_SEGMENT.test(segment) ? segment : REDACTED_SEGMENT))
    .join('/');
}

/**
 * A target that does not parse cannot be redacted segment by segment, and printing it raw is
 * exactly how an address would slip through, so only the failure is reported.
 */
export function describeTarget(href: string, base?: string): string {
  try {
    const url = new URL(href, base);
    return url.origin + redactPath(url.pathname);
  } catch {
    return UNPARSED_TARGET;
  }
}

/**
 * `init` wins over the Request it is passed alongside, the way fetch itself resolves the pair, so
 * a GET Request sent with `{ method: 'POST' }` is reported as the POST it becomes.
 */
export function describeRequest(input: RequestInfo | URL, init: RequestInit | undefined, base?: string): string {
  const request = typeof Request !== 'undefined' && input instanceof Request ? input : undefined;
  const method = init?.method ?? request?.method ?? 'GET';
  return `${method} ${describeTarget(hrefOf(input, request), base)}`;
}

/** Anything that is not one of the three shapes fetch accepts yields an empty target, which
 * `describeTarget` then reports as unparsed rather than stringifying an object into the log. */
function hrefOf(input: RequestInfo | URL, request: Request | undefined): string {
  if (request) return request.url;
  if (typeof input === 'string') return input;
  if (input instanceof URL) return input.href;
  return '';
}

interface FetchHost {
  fetch: typeof fetch;
  location?: { href: string };
}

export function installFetchLogging(host: FetchHost, log: (message: string) => void, now = () => performance.now()) {
  const originalFetch = host.fetch;

  host.fetch = async function loggedFetch(this: unknown, ...args: Parameters<typeof fetch>) {
    const target = describeRequest(args[0], args[1], host.location?.href);
    const startedAt = now();
    try {
      const response = await originalFetch.apply(this, args);
      log(`net status=${response.status} time=${seconds(now() - startedAt)} @ ${target}`);
      return response;
    } catch (error) {
      // A rejected fetch used to be as silent as a successful one, which is the wrong way round:
      // a request that never reached a status is the one worth seeing.
      log(`net failed=${errorName(error)} time=${seconds(now() - startedAt)} @ ${target}`);
      throw error;
    }
  } as typeof fetch;
}

function seconds(milliseconds: number): string {
  return (milliseconds / 1000).toFixed(3);
}

function errorName(error: unknown): string {
  return error instanceof Error && error.name ? error.name : 'Error';
}
