// Usage: node dev/export-card-backgrounds.cjs /path/to/mtw-cards-generator
// Preserve JavaScript's Object.keys ordering: numeric Texture Size keys precede Virgin.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const yaml = require('js-yaml');
const svgpath = require('svgpath');

const source = process.argv[2];
if (!source) throw new Error('Pass the mtw-cards-generator checkout path.');
const read = (name) => yaml.load(fs.readFileSync(path.join(source, 'src/data', `${name}.yaml`), 'utf8'));
const commands = (d) => {
  const result = [];
  svgpath(d).abs().unshort().unarc().iterate((segment, index, x, y) => {
    const [command, ...values] = segment;
    switch (command) {
      case 'M': result.push([0, ...values]); break;
      case 'L': result.push([1, ...values]); break;
      case 'H': result.push([1, values[0], y]); break;
      case 'V': result.push([1, x, values[0]]); break;
      case 'C': result.push([2, ...values]); break;
      case 'Q': result.push([3, ...values]); break;
      case 'Z': result.push([4]); break;
      default: throw new Error(`Unsupported SVG command ${command}`);
    }
  });
  return result;
};
const transform = (value) => {
  const p = svgpath('M0 0L1 0L0 1').transform(value).abs();
  const points = [];
  p.iterate((s) => points.push(s.slice(1)));
  const [[x, y], [xx, xy], [yx, yy]] = points;
  return [xx - x, xy - y, yx - x, yy - y, x, y];
};
const entries = (object, fn) => Object.fromEntries(Object.entries(object).map(([k, v]) => [k, fn(v)]));
const data = {
  revision: execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
  attributes: Object.entries(read('attributes')).map(([name, options]) => ({ name, options: Object.keys(options) })),
  backgrounds: entries(read('backgrounds'), (b) => ({
    fill: b.rectFill,
    transform: b.gradientTransform && transform(b.gradientTransform),
    stops: b.stops?.map((s) => ({ location: Number(s.offset), color: s['stop-color'] })),
  })),
  colors: read('colors'),
  textures: entries(read('textures'), (paths) => paths.map(commands)),
  spots: entries(read('spots'), (positions) => entries(positions, (s) => ({
    commands: commands(s.path),
    filter: ['x', 'y', 'width', 'height'].map((key) => Number(s.filter[key])),
  }))),
  shines: entries(read('shines'), (s) => transform(s.gradientTransform)),
};
const destination = path.join(__dirname, '../mobile/ios/Air/SubModules/UIComponents/Resources/CardBackgrounds');
fs.mkdirSync(destination, { recursive: true });
fs.writeFileSync(path.join(destination, 'CardBackgroundRecipes.json'), `${JSON.stringify(data)}\n`);
fs.copyFileSync(path.join(source, 'LICENSE'), path.join(destination, 'CardBackgroundGenerator-LICENSE.txt'));
console.log(`Exported ${Object.keys(data.textures).length} vector textures, ${Object.keys(data.backgrounds).length} backgrounds; revision ${data.revision}`);
