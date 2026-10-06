import { redactPath } from '../src/util/fetchLogging';

/**
 * Bakes `process.env.X` reads into the bundle: a variable set at build time wins, otherwise the listed
 * default is used.
 *
 * Only the listed keys are replaced. Any other `process.env.X` read stays in the code and resolves at
 * runtime against the injected `process/browser` shim, whose `env` is empty.
 *
 * Every key is also printed, because this is the only place that knows which value won. A build input
 * that was never set is indistinguishable from one deliberately left at its default once the bundle
 * exists, and that is not hypothetical: an unset `AGENT_API_URL` expands to an empty string, an empty
 * string is a value this function keeps, and the SDK fell through to the production Agent with no line
 * anywhere - not in the job log, not in the app - naming the host it had chosen.
 */

/**
 * Keys whose value is a credential rather than a setting. The report says a credential was supplied
 * and how long it is, which is what a build log needs, and never the credential itself.
 */
const CREDENTIAL_KEY = /(KEY|SECRET|TOKEN|PASSWORD|MNEMONIC|SESSION|PROJECT_ID|APP_ID)$/;

interface ResolvedValue {
  key: string;
  value: string;
  fromEnvironment: boolean;
}

export function defineEnv(defaults: Record<string, string>) {
  const resolved = resolveEnv(defaults, process.env);

  // eslint-disable-next-line no-console
  console.info(formatEnvReport(resolved).join('\n'));

  return Object.fromEntries(resolved.map(({ key, value }) => [`process.env.${key}`, JSON.stringify(value)]));
}

export function describeEnv(defaults: Record<string, string>, env: Record<string, string | undefined>): string[] {
  return formatEnvReport(resolveEnv(defaults, env));
}

/**
 * A key present in the environment is reported as such even when its value is empty. That case is the
 * interesting one - a repository variable that does not exist reaches the build as `''` rather than
 * disappearing - so collapsing it into "default" would hide the failure this report exists to show.
 */
function resolveEnv(defaults: Record<string, string>, env: Record<string, string | undefined>): ResolvedValue[] {
  return Object.entries(defaults).map(([key, fallback]) => ({
    key,
    value: env[key] ?? fallback,
    fromEnvironment: env[key] !== undefined,
  }));
}

function formatEnvReport(resolved: ResolvedValue[]): string[] {
  const fromEnvironment = resolved.filter((entry) => entry.fromEnvironment).length;
  const header = `Build-time env: ${resolved.length} keys baked in, ${fromEnvironment} supplied by the environment`;

  return [header, ...resolved.map((entry) => {
    const source = entry.fromEnvironment ? '[env]    ' : '[default]';
    return `  ${source} ${entry.key} = ${formatValue(entry.key, entry.value)}`;
  })];
}

function formatValue(key: string, value: string): string {
  if (!value) {
    return JSON.stringify(value);
  }
  if (CREDENTIAL_KEY.test(key)) {
    return `<supplied, ${value.length} chars>`;
  }
  return JSON.stringify(describeValue(value));
}

/**
 * A URL is printed as its origin and a redacted path, through the same boundary the running app
 * logs its requests with. Providers carry the API key in the path - `.../v2/<key>` is how Alchemy
 * is addressed - so printing URLs verbatim would leak credentials under key names that give no
 * hint of one, which is exactly what a name-based rule cannot catch.
 */
function describeValue(value: string): string {
  try {
    const url = new URL(value);
    return url.origin + redactPath(url.pathname) + (url.search ? '?<redacted>' : '');
  } catch {
    return value;
  }
}
