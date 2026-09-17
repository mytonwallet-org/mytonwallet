import assert from 'node:assert/strict';
import test from 'node:test';

import mtwConfig from '@mytonwallet/eslint-config';
import { ESLint } from 'eslint';
import tseslint from 'typescript-eslint';

import { FILE_NAMING_RULE as RULE_NAME } from './fileNamingPlugin.mjs';

const eslint = new ESLint({ overrideConfig: [tseslint.configs.disableTypeChecked] });

test('accepts components, companion files, hooks, JSX utilities, classes, and entrypoints', async () => {
  for (const filePath of [
    'src/components/agent/AgentMessageControls.tsx',
    'src/components/agent/AgentMessageControls.test.tsx',
    'src/components/agent/AnswerMessageContent.module.scss',
    'src/components/agent/hooks/useAgentMessages.tsx',
    'src/components/agent/hooks/agentMessages.test.tsx',
    'src/components/portfolio/helpers/useLovelyChart.module.scss',
    'src/mfa/components/_common.module.scss',
    'src/util/renderMarkdown.tsx',
    'src/util/Deferred.ts',
    'src/api/storages/nodeFile.worker.js',
    'src/types/index.d.ts',
    'src/api/migrations/00022.ts',
    'src/components/ui/index.tsx',
    'src/index.tsx',
  ]) {
    const content = filePath.endsWith('.scss') ? '.table { color: red; }' : '';
    const results = await eslint.lintText(content, { filePath });
    assert.equal(results.length, 1, filePath);
    assert.equal(results[0].fatalErrorCount, 0, filePath);
    assert.deepEqual(results[0].messages.filter(({ ruleId }) => ruleId === RULE_NAME), [], filePath);
  }
});

test('rejects kebab-case, snake_case, lowercase component names, and uppercase hooks', async () => {
  for (const filePath of [
    'src/components/agentV2/agent-message-controls.tsx',
    'src/components/agentV2/agent-message-controls.test.tsx',
    'src/components/agent/answer-message-content.module.scss',
    'src/components/agent/answerMessageContent.tsx',
    'src/components/agent/answerMessageContent.module.scss',
    'src/components/agent/Answer_MessageContent.tsx',
    'src/components/agent/hooks/UseAgentMessages.ts',
    'src/components/agent/hooks/agent-messages.test.tsx',
    'src/util/build-message.ts',
    'src/util/build_message.ts',
    'src/util/1message.ts',
  ]) {
    const results = await eslint.lintText('', { filePath });
    assert.equal(results.length, 1, filePath);
    assert.equal(results[0].fatalErrorCount, 0, filePath);
    const messages = results[0].messages.filter(({ ruleId }) => ruleId === RULE_NAME);
    assert.equal(messages.length, 1, filePath);
    assert.equal(messages[0].severity, 2, filePath);
    assert.match(messages[0].message, /Rename .*CODESTYLE.md/, filePath);
    assert.equal(messages[0].fix, undefined, filePath);
  }
});

test('preserves library entrypoint naming and native file scope', async () => {
  for (const filePath of [
    'src/lib/teact/jsx-runtime.ts',
    'src/lib/teact/teact-dom.ts',
    'src/lib/example/components/external-component.tsx',
    'src/api/agentV2/generated/external-contract.ts',
    'src/components/example/generated/external-component.tsx',
    'mobile/ios/External-File.swift',
  ]) {
    const results = await eslint.lintText('', { filePath });
    assert.deepEqual(results.flatMap(({ messages }) => messages.filter(({ ruleId }) => ruleId === RULE_NAME)), []);
  }
});

test('preserves shared JavaScript and TypeScript rule scopes when adding SCSS processing', async () => {
  const shared = new ESLint({ overrideConfigFile: true, overrideConfig: mtwConfig.configs.frontendRecommended });
  const project = new ESLint();
  for (const filePath of ['src/mfa/public/fallbackScript.js', 'src/util/schedulers.ts']) {
    const sharedConfig = await shared.calculateConfigForFile(filePath);
    const projectConfig = await project.calculateConfigForFile(filePath);
    const projectRules = { ...projectConfig.rules };
    delete projectRules[RULE_NAME];
    assert.deepEqual(projectRules, sharedConfig.rules, filePath);
  }
});
