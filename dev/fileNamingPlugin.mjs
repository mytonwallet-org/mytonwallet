import path from 'node:path';

export const FILE_NAMING_RULE = 'file-naming/case';

export function getExpectedFilename(filename, namingCase = 'mixedCase') {
  const [base, ...extensions] = filename.split('.');
  const words = base.split(/[-_ ]+/).filter(Boolean);
  let name = words.map((word, index) => index ? word[0].toUpperCase() + word.slice(1) : word).join('');
  if (!/^[a-zA-Z][a-zA-Z0-9]*$/.test(name)) return undefined;
  if (namingCase === 'pascalCase') name = name[0].toUpperCase() + name.slice(1);
  if (namingCase === 'camelCase') name = name[0].toLowerCase() + name.slice(1);
  return [name, ...extensions].join('.');
}

export default {
  meta: { name: 'mytonwallet-file-naming' },
  rules: {
    case: {
      meta: {
        type: 'layout',
        schema: [{ enum: ['mixedCase', 'camelCase', 'pascalCase'] }],
        messages: {
          rename: 'Rename "{{ current }}" to "{{ expected }}" (CODESTYLE.md). Run npm run fix:file-names to update references',
          invalid: 'Rename "{{ current }}" manually: its name cannot be inferred safely (CODESTYLE.md)',
        },
      },
      create(context) {
        return {
          Program(node) {
            const current = path.basename(context.physicalFilename);
            const expected = getExpectedFilename(current, context.options[0]);
            if (current === expected) return;
            context.report({
              node,
              messageId: expected ? 'rename' : 'invalid',
              data: { current, expected },
            });
          },
        };
      },
    },
  },
  processors: {
    filename: {
      preprocess: (text, filename) => [{ text: '', filename }],
      postprocess: (messages) => messages.flat(),
    },
  },
};
