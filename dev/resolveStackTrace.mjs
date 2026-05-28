import fs from 'fs';
import { SourceMapConsumer } from 'source-map';
import path from 'path';
import { fileURLToPath } from 'url';

const USAGE_GUIDE = `This script is intended to be used manually.
It makes JavaScript errors from user logs more readable by converting the stacktrace references from minified file addresses to source code addresses.

To use the script, build the application first.
Make sure the application version you build is the same as the version of the application that produced the logs.
Then run any of these commands:

  npm run resolve-stacktrace <error>
  npm run resolve-stacktrace <dist-directory> <error>

Where <error> is an error string from a log file exported by the application,
and <dist-directory> is the path to a directory with the application's sourcemaps (default: dist).
Examples:
my_TONwallet
  npm run resolve-stacktrace ${JSON.stringify('{"name":"Error","message":"Test","stack":"Error: Test\n    at t.BitBuilder.writeVarUint (https://mytonwallet.local/941.c17ba5754ec7f174fec2.js:2:25840)\n    at t.BitBuilder.writeCoins (https://mytonwallet.local/941.c17ba5754ec7f174fec2.js:2:26382)"}')}

  npm run resolve-stacktrace "Error: Test\n    at t.BitBuilder.writeVarUint (https://mytonwallet.local/941.c17ba5754ec7f174fec2.js:2:25840)\n    at t.BitBuilder.writeCoins (https://mytonwallet.local/941.c17ba5754ec7f174fec2.js:2:26382)"`;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DEFAULT_MAP_DIRECTORY = path.join(__dirname, '..', 'dist');

const { mapDirectory, stackTrace } = resolveArguments();
const resolvedStackTrace = await resolveStackTrace(mapDirectory, stackTrace);
process.stdout.write(`${resolvedStackTrace}\n`);
process.exit(0);

function resolveArguments() {
  const args = process.argv.slice(2);
  switch (args.length) {
    case 0:
      process.stderr.write(`Too few arguments!\n\n${USAGE_GUIDE}\n`)
      process.exit(1);
      break;
    case 1:
      return {
        mapDirectory: DEFAULT_MAP_DIRECTORY,
        stackTrace: parseStackTrace(args[0]),
      };
    case 2:
      return {
        mapDirectory: args[0],
        stackTrace: parseStackTrace(args[1]),
      };
    default:
      process.stderr.write(`Too many arguments!\n\n${USAGE_GUIDE}\n`)
      process.exit(1);
      break;
  }
}

function parseStackTrace(inputText) {
  const decoders = [parseJsonStackTrace, parsePlainStackTrace];

  for (const decoder of decoders) {
    const decoded = decoder(inputText);
    if (decoded) {
      return decoded;
    }
  }

  process.stderr.write(`Unknown input error format. Check the examples.\n\n${USAGE_GUIDE}\n`)
  process.exit(1);
}

// Decodes a line from a log file as is. For example:
// "{\"name\":\"TypeError\",\"message\":\"Cannot...
function parseJsonStackTrace(inputText) {
  let data
  try {
    data = JSON.parse(inputText);
  } catch {
    return null;
  }

  if (!data || typeof data !== 'object' || typeof data.stack !== 'string') {
    return null;
  }

  return data.stack;
}

function parsePlainStackTrace(inputText) {
  if (/^(.+)(\n.*:\d+:\d+)+$/.test(inputText)) {
    return inputText;
  }

  return null;
}

async function resolveStackTrace(mapDirectory, stackTrace) {
  const consumerCache = {};

  return (await Promise.all(stackTrace
    .split('\n')
    .map(line => resolveStackTraceLine(mapDirectory, consumerCache, line)))
  ).join('\n');
}

async function resolveStackTraceLine(mapDirectory, consumerCache, line) {
  const parsedLine = parseStackTraceLine(line);
  if (!parsedLine) {
    return line;
  }

  const newTrace = await resolveTrace(
    mapDirectory,
    consumerCache,
    parsedLine.fileUrl,
    parsedLine.lineNumber,
    parsedLine.columnNumber,
  );
  if (!newTrace) {
    return line;
  }

  return `${parsedLine.lineIndent}at ${newTrace.name ?? ''} ${newTrace.filePath}:${newTrace.lineNumber}:${newTrace.columnNumber}`;
}

function parseStackTraceLine(line) {
  // Example: at t.BitBuilder.writeCoins (https://mytonwallet.local/941.c17ba5754ec7f174fec2.js:2:26382)
  const chromeRegex1 = /^(\s*)at\s.+\((.+):(\d+):(\d+)\)\s*$/;
  // Example: at async https://mytonwallet.local/941.c17ba5754ec7f174fec2.js:2:1906473
  const chromeRegex2 = /^(\s*)at(?:\sasync)?\s(.+):(\d+):(\d+)\s*$/;
  // Example: safeExec@http://localhost:4321/main.0f90301c98b9aa1b7228.js:55739:14
  // Example: @http://localhost:4321/main.0f90301c98b9aa1b7228.js:49974:25
  // Example: ./src/lib/teact/teact.ts/runUpdatePassOnRaf</<@http://localhost:4321/main.0f90301c98b9aa1b7228.js:49974:32
  const safariAndFirefoxRegex = /^(\s*)\S*@(.+):(\d+):(\d+)\s*$/;

  const match = chromeRegex1.exec(line) || chromeRegex2.exec(line) || safariAndFirefoxRegex.exec(line);
  if (!match) {
    return null;
  }

  const [, lineIndent, fileUrl, lineNumber, columnNumber] = match;
  return { lineIndent, fileUrl, lineNumber: Number(lineNumber), columnNumber: Number(columnNumber) };
}

async function resolveTrace(mapDirectory, consumerCache, fileUrl, lineNumber, columnNumber) {
  const mapFile = findSourceMapFile(mapDirectory, fileUrl);
  if (!mapFile) {
    return null;
  }

  if (!consumerCache[mapFile]) {
    const sourceMap = JSON.parse(fs.readFileSync(path.join(mapDirectory, mapFile), 'utf8'));
    const consumer = new SourceMapConsumer(sourceMap);
    consumerCache[mapFile] = consumer;
  }

  const cache = await consumerCache[mapFile];
  const sourcePosition = cache.originalPositionFor({ line: lineNumber, column: columnNumber });
  if (sourcePosition.line === null) {
    return null;
  }

  return {
    name: sourcePosition.name,
    filePath: resolveSourceFilePath(sourcePosition.source),
    lineNumber: sourcePosition.line,
    columnNumber: sourcePosition.column,
  };
}

function findSourceMapFile(mapDirectory, fileUrl) {
  const filePath = extractFilePathFromUrl(fileUrl);
  const bundleId = extractBundleIdFromFilePath(filePath, '.js');
  if (bundleId === null) {
    return null;
  }

  const directoryContent = fs.readdirSync(mapDirectory, { withFileTypes: true });
  const isDesiredMap = (item) => item.isFile() && extractBundleIdFromFilePath(item.name, '.js.map') === bundleId;
  return directoryContent.find(isDesiredMap)?.name ?? null;
}

function extractFilePathFromUrl(fileUrl) {
  return fileUrl.replace(/^\w+:\/\/[^\/]*\//, '');
}

function extractBundleIdFromFilePath(filePath, extension) {
  if (!filePath.endsWith(extension)) {
    return null;
  }

  const match = /^([\w.-]*)\.[\w]{16,}$/.exec(filePath.slice(0, filePath.length - extension.length));
  if (!match) {
    return null;
  }

  return match[1];
}

function resolveSourceFilePath(sourceFileUrl) {
  return sourceFileUrl.replace(/^webpack:\/\/[^\/]*\//, '');
}
