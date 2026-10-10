import type { AgentRunRequestWireV2 } from './protocol/types';
import type { AgentV2RunCommand } from './types';

import { AgentV2HttpError } from './identity';

export type AgentV2RunOrigin = Partial<Pick<
  AgentRunRequestWireV2,
  'entryPoint' | 'followupOf'
>>;

export function buildAgentV2RunOrigin(command: AgentV2RunCommand): AgentV2RunOrigin {
  assertAgentV2RunCommandOrigin(command);
  switch (command.input.kind) {
    case 'edit':
    case 'regenerate':
      return {};
    case 'append':
      if (command.entryPoint) return { entryPoint: command.entryPoint };
      if (command.followupOf) return { followupOf: command.followupOf };
      return {};
    default:
      return assertUnreachable(command.input);
  }
}

export function assertAgentV2RunCommandOrigin(command: AgentV2RunCommand) {
  const inputKind = (command as { input?: { kind?: unknown } }).input?.kind;
  if (inputKind !== 'append' && inputKind !== 'edit' && inputKind !== 'regenerate') {
    throw invalidRunCommand();
  }
  const originCount = [
    command.entryPoint,
    command.followupOf,
  ].filter((value) => value !== undefined).length;
  if (originCount > 1 || (inputKind !== 'append' && originCount > 0)) {
    throw invalidRunCommand();
  }
}

function invalidRunCommand() {
  return new AgentV2HttpError(
    0,
    'invalid_request',
    'Agent run origin is invalid.',
    false,
  );
}

function assertUnreachable(value: never): never {
  throw new Error(`Unexpected Agent V2 value: ${String(value)}`);
}
