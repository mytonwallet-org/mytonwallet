import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const goDataContent = fs.readFileSync(path.join(__dirname, 'go.json'), 'utf8');
const goData = JSON.parse(goDataContent);

const templateContent = fs.readFileSync(path.join(__dirname, 'go', 'template.html'), 'utf8');

const REDIRECTS = [
  ['/.well-known/*', '/-well-known/:splat', '200'],
  ['/get/*', 'https://mytonwallet.app/get/:splat', '302'],
  ['/tx/ton/*', 'https://mtw-explorer.netlify.app/:splat', '200'],
  ['/tx/tron/*', 'https://mtw-explorer.netlify.app/:splat', '200'],
  ['/view/*', 'https://mtw-explorer.netlify.app/:splat', '200'],
  ['/nft/*', 'https://mtw-explorer.netlify.app/:splat', '200'],
];

fs.mkdirSync(path.join(__dirname, 'go', 'generated'), { recursive: true });

for (const [key, actionData] of Object.entries(goData)) {
  const template = templateContent
    .replaceAll('!{{TITLE}}', actionData.title)
    .replaceAll('!{{DESCRIPTION}}', actionData.description)
    .replaceAll('!{{ICON}}', actionData.icon);

  REDIRECTS.push([`/${key}`, `/generated/${key}.html`, '200']);
  REDIRECTS.push([`/${key}/*`, `/generated/${key}.html`, '200']);

  fs.writeFileSync(path.join(__dirname, 'go', 'generated', `${key}.html`), template);
}

REDIRECTS.push(['/*', '/generated/index.html', '200']);

const firstPartMaxLength = Math.max(...REDIRECTS.map(([from]) => from.length));
const secondPartMaxLength = Math.max(...REDIRECTS.map(([_1, to]) => to.length));
const thirdPartMaxLength = Math.max(...REDIRECTS.map(([_1, _2, status]) => status.length));

const redirectTemplate = `{{firstPart}} {{secondPart}} {{thirdPart}}`;

fs.writeFileSync(
  path.join(__dirname, 'go', '_redirects'),
  REDIRECTS.map(([from, to, status]) => redirectTemplate
    .replaceAll('{{firstPart}}', from.padEnd(firstPartMaxLength))
    .replaceAll('{{secondPart}}', to.padEnd(secondPartMaxLength))
    .replaceAll('{{thirdPart}}', status.padEnd(thirdPartMaxLength))
  ).join('\n')
);
