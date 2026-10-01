/**
 * Bakes `process.env.X` reads into the bundle: a variable set at build time wins, otherwise the listed
 * default is used.
 *
 * Only the listed keys are replaced. Any other `process.env.X` read stays in the code and resolves at
 * runtime against the injected `process/browser` shim, whose `env` is empty.
 */
export function defineEnv(defaults: Record<string, string>) {
  return Object.fromEntries(Object.entries(defaults).map(([key, defaultValue]) => [
    `process.env.${key}`,
    JSON.stringify(process.env[key] ?? defaultValue),
  ]));
}
