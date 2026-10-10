import type { AgentClientTrace } from './developmentTelemetry';
import type { AgentToolCall, AgentToolResultRequestV2 } from './protocol/types';

import { logDebug, logDebugError } from '../../util/logs';
import { decodeAgentV2ToolResultAck } from './protocol/transportContracts';
import { classifyAgentV2Error } from './errors';
import { AgentV2HttpError } from './identity';
import { getAgentToolExecutionTimeout } from './toolDeadline';

const TOOL_RESULT_MAX_ATTEMPTS = 3;
const RETRY_BASE_DELAY_MS = 250;
// A slow mobile uplink moves a couple of kilobytes a second, so a large result gets time to upload
const MIN_UPLOAD_BYTES_PER_SECOND = 2_048;

export interface AgentV2ToolExecutionContext {
  messageId: string;
  runId: string;
  threadId: string;
  signal: AbortSignal;
}

export interface AgentV2ToolExecutor {
  execute(toolCall: AgentToolCall, context: AgentV2ToolExecutionContext): Promise<AgentToolResultRequestV2>;
  discard?(toolCallId: string): void;
  clear?(threadId?: string): void;
}

interface AgentV2ToolRunnerDependencies {
  getJson: <T>(
    url: string,
    decoder: (value: unknown) => T,
    init: RequestInit,
    options: { trace?: AgentClientTrace; shouldSkipUnauthorizedRecovery?: boolean; timeoutMs?: number },
  ) => Promise<T>;
  baseUrl: string;
  executor: () => AgentV2ToolExecutor;
  discard: (toolCallId: string) => void;
  now: () => number;
  randomUuid: () => string;
  wait: (milliseconds: number, signal: AbortSignal) => Promise<void>;
  requestTimeoutMs: number;
}

export class AgentV2ToolRunner {
  constructor(private readonly dependencies: AgentV2ToolRunnerDependencies) {}

  execute(
    call: AgentToolCall,
    context: Omit<AgentV2ToolExecutionContext, 'signal'>,
    parentSignal: AbortSignal,
  ): Promise<AgentToolResultRequestV2> {
    return new Promise((resolve, reject) => {
      const controller = new AbortController();
      let hasTimedOut = false;
      let isSettled = false;
      const timeout = setTimeout(() => {
        if (isSettled) return;
        hasTimedOut = true;
        isSettled = true;
        dispose();
        resolve(this.createToolTimeoutResult(call, context));
        logDebugError('AgentV2 tool lifecycle', {
          stage: 'timeout',
          runId: context.runId,
          toolCallId: call.id,
          toolName: call.name,
          timeoutMs: call.timeoutMs,
        });
        controller.abort(new DOMException('Tool execution timed out.', 'TimeoutError'));
        this.dependencies.discard(call.id);
      }, getAgentToolExecutionTimeout(call.timeoutMs));
      const handleParentAbort = () => {
        if (isSettled) return;
        isSettled = true;
        dispose();
        controller.abort(parentSignal.reason);
        reject(parentSignal.reason ?? new DOMException('Aborted', 'AbortError'));
      };
      const dispose = () => {
        clearTimeout(timeout);
        parentSignal.removeEventListener('abort', handleParentAbort);
      };

      if (parentSignal.aborted) {
        handleParentAbort();
        return;
      }
      parentSignal.addEventListener('abort', handleParentAbort, { once: true });
      const execution = Promise.resolve().then(() => {
        if (controller.signal.aborted) {
          throw controller.signal.reason ?? new DOMException('Aborted', 'AbortError');
        }
        return this.dependencies.executor().execute(call, {
          ...context,
          signal: controller.signal,
        });
      });
      execution.then((toolResult) => {
        if (hasTimedOut) {
          this.dependencies.discard(call.id);
          return;
        }
        if (isSettled) return;
        isSettled = true;
        dispose();
        resolve(toolResult);
      }, (error) => {
        if (hasTimedOut) {
          this.dependencies.discard(call.id);
          return;
        }
        if (isSettled) return;
        isSettled = true;
        dispose();
        logDebugError('AgentV2 tool lifecycle', {
          stage: 'rejected',
          runId: context.runId,
          toolCallId: call.id,
          toolName: call.name,
        }, error);
        reject(error);
      });
    });
  }

  private createToolTimeoutResult(
    call: AgentToolCall,
    context: Omit<AgentV2ToolExecutionContext, 'signal'>,
  ): AgentToolResultRequestV2 {
    return {
      protocolVersion: 3,
      runId: context.runId,
      threadId: context.threadId,
      toolCallId: call.id,
      clientToolResultId: this.dependencies.randomUuid(),
      completedAt: new Date(this.dependencies.now()).toISOString(),
      ...toolResultSessionBinding(call),
      status: 'error',
      error: {
        code: 'tool_timeout',
        retryable: true,
      },
    };
  }

  async submit(
    runId: string,
    call: { id: string; name: string },
    result: AgentToolResultRequestV2,
    signal: AbortSignal,
    isCurrent: () => boolean,
    trace?: AgentClientTrace,
  ) {
    let lastError: unknown;
    const body = JSON.stringify(result);
    // Each attempt gets its own deadline, so one that gets no response is retried
    const timeoutMs = this.dependencies.requestTimeoutMs
      + Math.ceil(new TextEncoder().encode(body).length * 1_000 / MIN_UPLOAD_BYTES_PER_SECOND);
    for (let attempt = 0; attempt < TOOL_RESULT_MAX_ATTEMPTS; attempt += 1) {
      try {
        const acknowledgement = await this.dependencies.getJson(
          `${this.dependencies.baseUrl}/runs/${runId}/tool-results`,
          decodeAgentV2ToolResultAck,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', ...(trace ? { 'x-agent-trace-id': trace.traceId } : {}) },
            body,
            signal,
          },
          { shouldSkipUnauthorizedRecovery: true, trace, timeoutMs },
        );
        if (!isCurrent() || signal.aborted) {
          throw signal.reason ?? new DOMException('Aborted', 'AbortError');
        }
        if (acknowledgement.runId !== runId) {
          throw new AgentV2HttpError(0, 'invalid_event', 'Agent response changed its run binding.', false);
        }
        if (
          acknowledgement.toolCallId !== call.id
          || acknowledgement.clientToolResultId !== result.clientToolResultId
        ) {
          throw new AgentV2HttpError(
            0,
            'invalid_event',
            'Agent tool acknowledgement changed its request binding.',
            false,
          );
        }
        logDebug('AgentV2 tool lifecycle', {
          stage: 'acknowledged',
          runId,
          toolCallId: call.id,
          toolName: call.name,
          status: result.status,
        });
        return;
      } catch (error) {
        lastError = error;
        logDebugError('AgentV2 tool result submission', {
          stage: 'failed',
          attempt: attempt + 1,
          runId,
          toolCallId: call.id,
          toolName: call.name,
        }, error);
        if (signal.aborted || !classifyAgentV2Error(error).retryable
          || (error instanceof AgentV2HttpError
            && (error.status === 413 || error.code === 'tool_result_too_large'))) break;
        await this.dependencies.wait(RETRY_BASE_DELAY_MS * (attempt + 1), signal);
      }
    }
    throw lastError;
  }
}

function toolResultSessionBinding(call: AgentToolCall) {
  return call.name === 'wallet.directory.query'
    ? { toolName: call.name, directorySession: call.directorySession }
    : { toolName: call.name, walletContextSession: call.walletContextSession };
}
