import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const capPlatform = process.env.CAP_PLATFORM;
const isIosCapacitorBuild = process.env.IS_CAPACITOR === '1' && (!capPlatform || capPlatform === 'ios');

if (!isIosCapacitorBuild) {
  process.exit(0);
}

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const iosPublicDir = path.join(rootDir, 'mobile', 'ios', 'App', 'App', 'public');
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mtw-ios-icons-'));
const fantasticonBin = path.join(rootDir, 'node_modules', '@twbs', 'fantasticon', 'bin', 'fantasticon');

try {
  if (!fs.existsSync(iosPublicDir)) {
    throw new Error(`Could not find iOS public directory at ${iosPublicDir}`);
  }

  execFileSync(process.execPath, [
    fantasticonBin,
    '--font-types',
    'ttf',
    '--asset-types',
    'css',
    '--output',
    tempDir,
    '--silent',
  ], {
    cwd: rootDir,
    stdio: 'inherit',
  });

  fs.copyFileSync(path.join(tempDir, 'brilliant-icons.ttf'), path.join(iosPublicDir, 'brilliant-icons.ttf'));

  const iconFontFace = '@font-face{font-family:"brilliant-icons";src:url(brilliant-icons.ttf) format("truetype");font-weight:normal;font-style:normal;font-display:block}';
  const fontFacePattern = /@font-face\s*\{\s*font-family:\s*["']brilliant-icons["'];[\s\S]*?\}/;
  const cssFiles = fs.readdirSync(iosPublicDir).filter((fileName) => fileName.endsWith('.css'));
  let patchedCssCount = 0;

  for (const cssFile of cssFiles) {
    const cssPath = path.join(iosPublicDir, cssFile);
    const css = fs.readFileSync(cssPath, 'utf8');

    if (!css.includes('brilliant-icons')) {
      continue;
    }

    const nextCss = css.replace(fontFacePattern, iconFontFace);

    if (nextCss === css) {
      if (css.includes(iconFontFace)) {
        patchedCssCount += 1;
        continue;
      }

      throw new Error(`Could not replace brilliant-icons @font-face in ${cssFile}`);
    }

    fs.writeFileSync(cssPath, nextCss);
    patchedCssCount += 1;
  }

  if (patchedCssCount === 0) {
    throw new Error('Could not find a built CSS file containing brilliant-icons');
  }

  for (const fileName of fs.readdirSync(iosPublicDir)) {
    if (/^brilliant-icons\..*\.woff2?$/.test(fileName)) {
      fs.rmSync(path.join(iosPublicDir, fileName));
    }
  }

  console.log('Prepared iOS public icon font assets');
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}
