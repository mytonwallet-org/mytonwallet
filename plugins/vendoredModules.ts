import path from 'path';
import type { Plugin } from 'vite';

interface ModuleWrapper {
  prologue: string;
  epilogue: string;
}

// Gives a CommonJS or UMD file a local `module` and `exports` to write to, which also makes UMD wrappers
// take their CommonJS branch, and re-exports the result as the default export
const COMMONJS_WRAPPER: ModuleWrapper = {
  prologue: 'const module = { exports: {} }; const exports = module.exports; ',
  epilogue: '\nexport default module.exports;\n',
};

// The library is an ES module compiled to UMD, so its exports stay named
const NOBLE_ED25519_WRAPPER: ModuleWrapper = {
  prologue: COMMONJS_WRAPPER.prologue,
  epilogue: '\nexport const { CURVE, ExtendedPoint, Point, RistrettoPoint, Signature, curve25519, getPublicKey, '
    + 'getSharedSecret, sign, sync, utils, verify } = module.exports;\n',
};

/**
 * Turns the vendored libraries in `src/lib` that are not ES modules into ones, leaving their files as
 * published.
 *
 * The dev server serves source files as native ES modules and converts CommonJS only for dependencies, so
 * these files would fail there as they are. Wrapping them the same way in builds keeps both modes equal.
 */
export function vendoredModules(libDir: string): Plugin {
  const wrappers: Record<string, ModuleWrapper> = {
    [path.join(libDir, 'quantize.js')]: COMMONJS_WRAPPER,
    [path.join(libDir, 'aes-js/index.js')]: COMMONJS_WRAPPER,
    [path.join(libDir, 'noble-ed25519/index.js')]: NOBLE_ED25519_WRAPPER,
  };

  return {
    name: 'mtw:vendored-modules',
    enforce: 'pre',
    transform: {
      filter: { id: { include: Object.keys(wrappers) } },
      handler(code, id) {
        const { prologue, epilogue } = wrappers[id];
        // `null` keeps the incoming map, which stays valid because the original lines do not move
        // eslint-disable-next-line no-null/no-null
        return { code: `${prologue}${code}${epilogue}`, map: null };
      },
    },
  };
}
