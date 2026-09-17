import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { ESLint } from 'eslint';
import ts from 'typescript';

import { FILE_NAMING_RULE, getExpectedFilename } from './fileNamingPlugin.mjs';

const SOURCE_EXTENSION = /\.(?:[cm]?[jt]sx?)$/;
const TEXT_EXTENSION = /\.(?:[cm]?[jt]sx?|json|md|ya?ml|s?css|html|sh|py|swift|kt)$/;
const RESOLUTION_EXTENSIONS = ['', '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.scss', '.css'];

export async function createFileRenamePlan(cwd = process.cwd()) {
  const root = fs.realpathSync(execFileSync('git', ['rev-parse', '--show-toplevel'], {
    cwd, encoding: 'utf8',
  }).trim());
  const eslint = new ESLint({ cwd: root });
  const inventory = [...new Set(execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], {
    cwd: root, encoding: 'utf8',
  }).split('\0').filter(Boolean))];
  const files = inventory.map((file) => path.join(root, file)).filter((file) => fs.existsSync(file));
  const renames = new Map();

  for (const file of files) {
    if (!SOURCE_EXTENSION.test(file) && !file.endsWith('.module.scss')) continue;
    const config = await eslint.calculateConfigForFile(file);
    const rule = config?.rules?.[FILE_NAMING_RULE];
    if (!rule?.[0]) continue;
    const current = path.basename(file);
    const expected = getExpectedFilename(current, rule[1]);
    if (current === expected) continue;
    if (!expected) throw new Error(`Cannot infer a filename for ${path.relative(root, file)}; rename it manually`);
    if (fs.realpathSync(file) !== file || !fs.lstatSync(file).isFile()) {
      throw new Error(`Cannot rename a symbolic link: ${path.relative(root, file)}`);
    }
    renames.set(file, path.join(path.dirname(file), expected));
  }

  validateDestinations(renames);
  for (const file of files) {
    if (fs.lstatSync(file).isSymbolicLink() && renames.has(fs.realpathSync(file))) {
      throw new Error(`Cannot rename a file referenced by a symbolic link: ${path.relative(root, file)}`);
    }
  }
  const originals = new Map();
  const updates = new Map();
  if (!renames.size) return { root, renames, originals, updates };

  const compilerOptions = readCompilerOptions(root);
  const resolutionCache = ts.createModuleResolutionCache(root, (file) => file, compilerOptions);
  for (const file of files) {
    if (!TEXT_EXTENSION.test(file) || !fs.lstatSync(file).isFile() || fs.realpathSync(file) !== file) continue;
    const original = fs.readFileSync(file, 'utf8');
    let updated = updateLiteralReferences(original, file, root, renames, compilerOptions, resolutionCache);
    if (!SOURCE_EXTENSION.test(file)) updated = updateRootReferences(updated, root, renames);
    if (updated !== original) updates.set(file, updated);
    if (updated !== original || renames.has(file)) originals.set(file, original);
  }

  return { root, renames, originals, updates };
}

export function applyFileRenamePlan(plan) {
  const { root, renames, originals, updates } = plan;
  if (!renames.size) return;
  for (const [file, original] of originals) {
    if (fs.realpathSync(file) !== file || fs.readFileSync(file, 'utf8') !== original) {
      throw new Error(`File changed while planning: ${path.relative(root, file)}; run the command again`);
    }
  }
  validateDestinations(renames);

  const backupDirectory = fs.mkdtempSync(path.join(root, '.file-naming-'));
  const backups = new Map();
  const created = [];
  const written = [];
  let isRecovered = false;
  try {
    // Moving sources aside also permits case-only renames on case-insensitive filesystems
    for (const file of renames.keys()) {
      const backup = path.join(backupDirectory, String(backups.size));
      fs.renameSync(file, backup);
      backups.set(file, backup);
    }
    for (const [file, target] of renames) {
      const backup = backups.get(file);
      const mode = fs.statSync(backup).mode & 0o777;
      const descriptor = fs.openSync(target, 'wx', mode);
      created.push(target);
      try {
        fs.writeFileSync(descriptor, updates.get(file) ?? fs.readFileSync(backup));
        fs.fchmodSync(descriptor, mode);
      } finally {
        fs.closeSync(descriptor);
      }
    }
    for (const [file, text] of updates) {
      if (renames.has(file)) continue;
      written.push(file);
      fs.writeFileSync(file, text);
    }
    isRecovered = true;
  } catch (error) {
    try {
      for (const file of written) fs.writeFileSync(file, originals.get(file));
      for (const file of created) fs.unlinkSync(file);
      for (const [file, backup] of backups) fs.renameSync(backup, file);
      isRecovered = true;
    } catch (recoveryError) {
      throw new AggregateError([error, recoveryError], `Rename failed; recovery files remain in ${backupDirectory}`);
    }
    throw error;
  } finally {
    if (isRecovered) fs.rmSync(backupDirectory, { recursive: true });
  }
}

function validateDestinations(renames) {
  const planned = new Set();
  for (const [file, target] of renames) {
    const key = target.toLowerCase();
    const hasExistingTarget = fs.readdirSync(path.dirname(target)).some((name) =>
      name.toLowerCase() === path.basename(target).toLowerCase() && name !== path.basename(file));
    if (hasExistingTarget || planned.has(key)) {
      throw new Error(`Filename collision: ${target}; no files were changed`);
    }
    planned.add(key);
  }
}

function readCompilerOptions(root) {
  const filename = path.join(root, 'tsconfig.json');
  if (!fs.existsSync(filename)) return { allowJs: true, moduleResolution: ts.ModuleResolutionKind.Node10 };
  const result = ts.readConfigFile(filename, ts.sys.readFile);
  if (result.error) throw new Error(ts.flattenDiagnosticMessageText(result.error.messageText, '\n'));
  const parsed = ts.parseJsonConfigFileContent(result.config, ts.sys, root);
  if (parsed.errors.length) {
    throw new Error(parsed.errors.map((error) => ts.flattenDiagnosticMessageText(error.messageText, '\n')).join('\n'));
  }
  return parsed.options;
}

function updateLiteralReferences(text, file, root, renames, compilerOptions, resolutionCache) {
  const replaceReference = (value) => {
    const pathname = value.split(/[?#]/, 1)[0];
    if (/^[a-z]+:/i.test(pathname) || Object.hasOwn(compilerOptions.paths || {}, pathname)) return value;
    const resolved = ts.resolveModuleName(pathname, file, compilerOptions, ts.sys, resolutionCache)
      .resolvedModule?.resolvedFileName;
    let original = resolved && renames.has(resolved) ? resolved : undefined;
    if (!original && (pathname.startsWith('.') || pathname.startsWith('src/') || /\.s?css$/.test(file))) {
      const absolute = path.resolve(pathname.startsWith('src/') ? root : path.dirname(file), pathname);
      // Stop at the first existing file, even when another extension is being renamed
      const candidate = RESOLUTION_EXTENSIONS.map((extension) => absolute + extension)
        .find((entry) => fs.existsSync(entry));
      if (renames.has(candidate)) original = candidate;
    }
    if (!original) return value;
    const oldBase = path.basename(original).split('.')[0];
    const newBase = path.basename(renames.get(original)).split('.')[0];
    const offset = pathname.lastIndexOf('/') + 1;
    const basename = pathname.slice(offset);
    if (basename !== oldBase && !basename.startsWith(`${oldBase}.`)) return value;
    return value.slice(0, offset) + newBase + value.slice(offset + oldBase.length);
  };

  if (!SOURCE_EXTENSION.test(file)) {
    if (!/\.s?css$/.test(file)) return text;
    return text.replace(/(@(?:use|forward|import)\s+|url\(\s*)(['"])([^'"\r\n]*)\2/g, (literal, prefix, quote, value) => {
      const replacement = replaceReference(value);
      return replacement === value ? literal : prefix + quote + replacement + quote;
    });
  }
  const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true);
  const edits = [];
  function visit(node) {
    if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) {
      const replacement = isModuleReference(node) ? replaceReference(node.text)
        : isFilePathArgument(node) ? updateRootReferences(node.text, root, renames) : node.text;
      if (replacement !== node.text) {
        const start = node.getStart(source);
        const quote = text[start];
        const escaped = replacement.replace(/\\/g, '\\\\').replaceAll(quote, `\\${quote}`);
        edits.push({ start: start + 1, end: node.end - 1, text: escaped });
      }
    }
    ts.forEachChild(node, visit);
  }
  visit(source);
  for (const edit of edits.sort((left, right) => right.start - left.start)) {
    text = text.slice(0, edit.start) + edit.text + text.slice(edit.end);
  }
  return text;
}

function isModuleReference(node) {
  const parent = node.parent;
  if ((ts.isImportDeclaration(parent) || ts.isExportDeclaration(parent)) && parent.moduleSpecifier === node) return true;
  if (ts.isExternalModuleReference(parent)) return true;
  if (ts.isLiteralTypeNode(parent) && ts.isImportTypeNode(parent.parent)) return true;
  if ((!ts.isCallExpression(parent) && !ts.isNewExpression(parent)) || parent.arguments?.[0] !== node) return false;
  const callee = parent.expression;
  if (callee.kind === ts.SyntaxKind.ImportKeyword) return true;
  if (ts.isIdentifier(callee)) return ['require', 'URL', 'Worker', 'SharedWorker'].includes(callee.text);
  if (!ts.isPropertyAccessExpression(callee) || !ts.isIdentifier(callee.expression)) return false;
  if (callee.expression.text === 'require') return callee.name.text === 'resolve';
  return ['jest', 'vi'].includes(callee.expression.text)
    && ['mock', 'doMock', 'unmock', 'requireActual', 'requireMock', 'unstable_mockModule'].includes(callee.name.text);
}

function isFilePathArgument(node) {
  const parent = node.parent;
  if (!ts.isCallExpression(parent) || parent.arguments[0] !== node) return false;
  const callee = parent.expression;
  const name = ts.isIdentifier(callee) ? callee.text : ts.isPropertyAccessExpression(callee) ? callee.name.text : '';
  return ['readFile', 'readFileSync', 'createReadStream', 'existsSync', 'stat', 'statSync', 'access', 'accessSync']
    .includes(name);
}

function updateRootReferences(text, root, renames) {
  for (const [file, target] of renames) {
    const from = path.relative(root, file).split(path.sep).join('/');
    const to = path.relative(root, target).split(path.sep).join('/');
    for (const [oldPath, newPath] of [[from, to], [from.slice(0, -path.extname(from).length),
      to.slice(0, -path.extname(to).length)]]) {
      const pattern = oldPath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const expression = new RegExp(`(?<![\\w/.:~-])(\\./)?${pattern}(?=$|[\\s"'\x60):,?#])`, 'g');
      text = text.replace(expression, (match, prefix = '') => prefix + newPath);
    }
  }
  return text;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  try {
    const args = process.argv.slice(2);
    if (args.some((arg) => arg !== '--dry-run')) throw new Error('Usage: node dev/fixFileNames.mjs [--dry-run]');
    const plan = await createFileRenamePlan();
    for (const [from, to] of plan.renames) console.log(`${path.relative(plan.root, from)} -> ${path.relative(plan.root, to)}`);
    for (const file of plan.updates.keys()) console.log(`Update references: ${path.relative(plan.root, file)}`);
    if (!args.includes('--dry-run')) applyFileRenamePlan(plan);
    const action = args.includes('--dry-run') ? 'Planned' : 'Renamed';
    console.log(`${action} ${plan.renames.size} files; ${plan.updates.size} files with reference updates`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
