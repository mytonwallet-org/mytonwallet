import fs from 'fs';
import path from 'path';
import type { Plugin } from 'vite';
import { normalizePath, parseAst } from 'vite';

const STUB_ID_PREFIX = '\0mtw-disabled-import:';

interface DisabledImport {
  importer: string;
  source: string;
  flag: string;
}

/**
 * The imports each `NO_*` flag switches off, keyed by the file that makes them. The file uses what it imports from
 * there only inside `if (process.env.<FLAG> !== '1')`.
 */
const DISABLED_IMPORTS: Record<string, Record<string, string[]>> = {
  NO_TON: {
    'src/api/chains/index.ts': ['./ton'],
    'src/api/methods/auth.ts': ['../chains/ton'],
  },
  NO_TRON: { 'src/api/chains/index.ts': ['./tron'] },
  NO_SOLANA: { 'src/api/chains/index.ts': ['./solana'] },
  NO_EVM: { 'src/api/chains/index.ts': ['./evm'] },
  NO_UTXO: { 'src/api/chains/index.ts': ['./utxo'] },
  NO_EXTRA_FEATURES: {
    'src/api/chains/ton/index.ts': ['./mfa', './staking'],
    'src/api/chains/ton/polling.ts': ['./staking'],
    'src/api/chains/ton/util/signer.ts': ['./encryption'],
    'src/api/dappProtocols/index.ts': ['./adapters/walletConnect'],
    'src/api/methods/auth.ts': ['./agentV2Lifecycle'],
    'src/api/methods/init.ts': ['./agentV2Lifecycle', './extra'],
    'src/api/methods/optional.ts': ['./agentV2Lifecycle', './mfa', './staking', './swap'],
    'src/api/methods/other.ts': ['../../assets/receiveGradientSvgs'],
    'src/api/methods/registry.ts': ['./agentV2', './extra'],
  },
};

/**
 * Leaves out of the build every import from `DISABLED_IMPORTS` whose flag is set, together with everything only
 * that import pulls in.
 *
 * Tree-shaking alone is not enough: it keeps the dependencies whose top-level code it cannot prove free of side
 * effects, such as `tronweb`, which is hundreds of kilobytes. So the import resolves to a stub instead. The stub
 * exports the names the file uses, and each of them throws if called.
 *
 * The plugin also bakes the flag into the code. That makes the branch statically false in every build, even in
 * one whose own list of `process.env` keys lacks the flag, so the stub is never reached.
 *
 * The build fails where the guarantee would otherwise break without anyone noticing:
 * - a file from `DISABLED_IMPORTS` is missing, or no longer makes the import, so the module would be bundled;
 * - a module the flag leaves out reaches the bundle anyway, through an import missing from `DISABLED_IMPORTS`;
 * - a stub reaches the bundle, so a name is used outside the flag branch and would throw at runtime.
 */
export function disabledImports(rootDir: string): Plugin {
  const enabledFlags = Object.keys(DISABLED_IMPORTS).filter((flag) => process.env[flag] === '1');
  const disabledImportList: DisabledImport[] = [];
  for (const [flag, importsByFile] of Object.entries(DISABLED_IMPORTS)) {
    for (const [file, sources] of Object.entries(importsByFile)) {
      const importer = normalizePath(path.join(rootDir, file));
      if (!fs.existsSync(importer)) {
        throw new Error(`${file}, listed for ${flag} in plugins/disabledImports.ts, does not exist`);
      }
      if (enabledFlags.includes(flag)) {
        sources.forEach((source) => disabledImportList.push({ importer, source, flag }));
      }
    }
  }
  const importers = new Set(disabledImportList.map(({ importer }) => importer));
  const bundledImporters = new Set<string>();
  const replacedIndexes = new Set<number>();
  // The modules themselves, by id: any file can import one, not only those listed
  const disabledModules = new Map<string, DisabledImport>();

  // The stub id carries the list index: a path in it would end up in the stub's dev server URL, where the
  // browser collapses `../` and garbles it
  const getStubImport = (id: string) => (
    id.startsWith(STUB_ID_PREFIX) ? disabledImportList[Number(id.slice(STUB_ID_PREFIX.length))] : undefined
  );

  return {
    name: 'mtw:disabled-imports',
    enforce: 'pre',

    config() {
      return {
        define: Object.fromEntries(enabledFlags.map((flag) => [`process.env.${flag}`, JSON.stringify('1')])),
      };
    },

    async buildStart() {
      await Promise.all(disabledImportList.map(async (item) => {
        const resolved = await this.resolve(item.source, item.importer, { skipSelf: true });
        if (!resolved) {
          this.error(`${item.source}, listed for ${item.flag} in plugins/disabledImports.ts, cannot be resolved `
            + `from ${path.relative(rootDir, item.importer)}`);
        }
        disabledModules.set(resolved.id, item);
      }));
    },

    resolveId(source, importer) {
      if (!importer || !importers.has(importer)) return undefined;

      bundledImporters.add(importer);
      const index = disabledImportList.findIndex((item) => item.importer === importer && item.source === source);
      if (index === -1) return undefined;

      replacedIndexes.add(index);
      return `${STUB_ID_PREFIX}${index}`;
    },

    load(id) {
      const stubImport = getStubImport(id);
      if (!stubImport) return undefined;

      const { importer, source, flag } = stubImport;
      const names = collectImportedNames(fs.readFileSync(importer, 'utf8'), source);
      const message = `${source} is left out of this build by ${flag}`;

      return `function disabled() { throw new Error(${JSON.stringify(message)}); }\n`
        + `export { ${[...names].map((name) => `disabled as ${name}`).join(', ')} };\n`;
    },

    buildEnd(error) {
      if (error) return;

      disabledImportList.forEach(({ importer, source, flag }, index) => {
        if (!bundledImporters.has(importer) || replacedIndexes.has(index)) return;

        this.error(`${path.relative(rootDir, importer)} no longer imports ${source}, so ${flag} cannot leave it out. `
          + 'Update plugins/disabledImports.ts');
      });
    },

    generateBundle(_, bundle) {
      for (const item of Object.values(bundle)) {
        if (item.type !== 'chunk') continue;

        for (const [id, { renderedLength }] of Object.entries(item.modules)) {
          if (!renderedLength) continue;

          const stubImport = getStubImport(id);
          if (stubImport) {
            const { importer, source, flag } = stubImport;
            this.error(`${path.relative(rootDir, importer)} uses what it imports from ${source} outside `
              + `\`if (process.env.${flag} !== '1')\`, and a ${flag} build leaves that module out`);
          }

          const disabledModule = disabledModules.get(id);
          if (disabledModule) {
            const moduleImporters = (this.getModuleInfo(id)?.importers ?? [])
              .map((importer) => path.relative(rootDir, importer));
            this.error(`${path.relative(rootDir, id)} is in the bundle although ${disabledModule.flag} leaves it out. `
              + `It is imported by ${moduleImporters.join(', ')}: list those imports in plugins/disabledImports.ts`);
          }
        }
      }
    },
  };
}

// The names `code` takes from `source`: named and default imports, and the members read off a namespace import
function collectImportedNames(code: string, source: string) {
  const program = parseAst(code, { lang: 'ts' });
  const names = new Set<string>();
  const namespaces = new Set<string>();

  for (const node of program.body) {
    if (node.type !== 'ImportDeclaration' || node.source.value !== source || node.importKind === 'type') continue;

    for (const specifier of node.specifiers) {
      if (specifier.type === 'ImportNamespaceSpecifier') {
        namespaces.add(specifier.local.name);
      } else if (specifier.type === 'ImportDefaultSpecifier') {
        names.add('default');
      } else if (specifier.importKind !== 'type') {
        const { imported } = specifier;
        names.add(imported.type === 'Identifier' ? imported.name : String(imported.value));
      }
    }
  }

  if (namespaces.size) {
    walk(program, (node) => {
      if (node.type === 'MemberExpression' && !node.computed && node.object.type === 'Identifier'
        && namespaces.has(node.object.name)) {
        names.add(node.property.name);
      }
    });
  }

  return names;
}

function walk(node: unknown, visit: (node: AnyLiteral) => void) {
  if (!node || typeof node !== 'object') return;

  if (Array.isArray(node)) {
    node.forEach((child) => walk(child, visit));
    return;
  }

  visit(node as AnyLiteral);
  Object.values(node).forEach((child) => walk(child, visit));
}
