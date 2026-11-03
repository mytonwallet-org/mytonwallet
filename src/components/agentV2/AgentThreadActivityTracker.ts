import type { AgentV2ClientUpdate } from '../../api/agentV2/types';

import { getAgentRunActivityLangKey } from '../agent/AgentRunActivity';

interface ActivityEntry {
  /** Absent for a status a loaded chat reported on its own */
  runId?: string;
  langKey: string;
  updatedAt: number;
}

/** The last status of an answer that completed, kept until the list shows the answer's preview */
interface HeldActivity {
  langKey: string;
  /** The list loads started before the answer completed */
  loadCount: number;
  /** The thread's revision when the run started */
  runRevision?: number;
}

const ANALYZING_LANG_KEY = '$agent_activity_analyzing_request';
const WRITING_LANG_KEY = '$agent_activity_writing';
// A thread without updates for this long and without a loaded chat to vouch for its run is no longer shown answering
export const ACTIVITY_STALE_INTERVAL_MS = 3 * 60 * 1000;
const FINISHED_RUN_LIMIT = 64;

/**
 * What the Agent is doing in each chat while it answers, for the chat list's status line, from the SDK's run
 * updates: the analysis until its first step, each step the server reports, then the writing of the answer until it
 * completes or the run ends. Every method returns the threads whose status changed.
 */
export default class AgentThreadActivityTracker {
  private entries = new Map<string, ActivityEntry>();

  private held = new Map<string, HeldActivity>();

  private runRevisions = new Map<string, number>();

  // Runs whose answer completed or that ended, oldest first: their late step updates are ignored
  private finishedRunIds: string[] = [];

  getLangKey(threadId: string) {
    return this.entries.get(threadId)?.langKey ?? this.held.get(threadId)?.langKey;
  }

  /** The chats answering now; a held status no longer counts */
  getAnsweringThreadIds() {
    return new Set(this.entries.keys());
  }

  handleUpdate(update: AgentV2ClientUpdate, now: number, loadCount: number): Set<string> {
    switch (update.kind) {
      case 'runStarted':
        this.held.delete(update.threadId);
        this.runRevisions.set(update.threadId, update.threadRevision);
        this.unfinishRun(update.runId);
        return this.set(update.threadId, update.runId, ANALYZING_LANG_KEY, now);
      case 'toolActivityChanged':
        if (this.isRunFinished(update.runId)) return new Set();
        return this.set(update.threadId, update.runId, getAgentRunActivityLangKey(update.status === 'running'
          ? { kind: 'tool', toolName: update.toolName, ...(update.operation && { operation: update.operation }) }
          : { kind: 'preparingResponse' }), now);
      case 'runActivityChanged':
        // The chat shows only the steps in progress, and so does its row
        if (
          this.isRunFinished(update.runId)
          || update.event.status !== 'active'
          || update.event.code === 'analysis.computing'
        ) {
          return new Set();
        }
        return this.set(
          update.threadId, update.runId, getAgentRunActivityLangKey({ kind: 'server', code: update.event.code }), now,
        );
      case 'messageStarted':
        // A run that goes on to another message is answering again
        this.unfinishRun(update.runId);
        return new Set();
      case 'textDelta':
      case 'semanticContentAvailable':
        this.unfinishRun(update.runId);
        return this.set(update.threadId, update.runId, WRITING_LANG_KEY, now);
      case 'messageCompleted':
        this.hold(update.threadId, update.runId, loadCount);
        return this.finish(update.threadId, update.runId);
      case 'runCancelled':
        return this.finish(update.threadId, update.runId);
      case 'runFailed': {
        const { threadId } = update;
        return threadId ? this.finish(threadId, update.runId) : new Set();
      }
      case 'walletAuthorityChanged':
        // Losing the wallet's authority without a thread ends every run
        return !update.threadId && !update.preservesActiveRuns ? this.removeAll() : new Set();
      default:
        return new Set();
    }
  }

  /** The open chat knows whether it is answering, so it shows a run the list missed and ends one it missed the end of */
  syncWithLoadedChat(threadId: string, langKey: string | undefined, now: number): Set<string> {
    if (!langKey) {
      return this.entries.delete(threadId) && !this.held.has(threadId) ? new Set([threadId]) : new Set();
    }
    if (this.entries.has(threadId)) return new Set();

    this.entries.set(threadId, { langKey, updatedAt: now });
    return new Set([threadId]);
  }

  /** Drops the statuses that went quiet, except the one the open chat vouches for */
  removeStale(now: number, loadedThreadId?: string): Set<string> {
    const changed = new Set<string>();
    this.entries.forEach(({ updatedAt }, threadId) => {
      if (threadId === loadedThreadId || now - updatedAt <= ACTIVITY_STALE_INTERVAL_MS) return;
      this.entries.delete(threadId);
      if (!this.held.has(threadId)) changed.add(threadId);
    });
    return changed;
  }

  /**
   * Ends the held statuses of the answers that a list load brings the previews of: those that completed before the
   * load started, and those of threads the load has past their run's revision
   */
  releaseAnswered(loadCount: number, revisions: Map<string, number>): Set<string> {
    const released = [...this.held.entries()]
      .filter(([threadId, hold]) => {
        if (hold.loadCount < loadCount) return true;
        const revision = revisions.get(threadId);
        return hold.runRevision !== undefined && revision !== undefined && revision > hold.runRevision;
      })
      .map(([threadId]) => threadId);
    return this.releaseHeld(released, loadCount);
  }

  /** Ends the held statuses that are still waiting for the list loads that `loadCount` counted */
  releaseHeld(threadIds: string[], loadCount?: number): Set<string> {
    const changed = new Set<string>();
    threadIds.forEach((threadId) => {
      const hold = this.held.get(threadId);
      if (!hold || (loadCount !== undefined && hold.loadCount > loadCount)) return;
      this.held.delete(threadId);
      if (!this.entries.has(threadId)) changed.add(threadId);
    });
    return changed;
  }

  removeThread(threadId: string): Set<string> {
    this.runRevisions.delete(threadId);
    const hasStatus = this.getLangKey(threadId) !== undefined;
    this.entries.delete(threadId);
    this.held.delete(threadId);
    return hasStatus ? new Set([threadId]) : new Set();
  }

  removeAll(): Set<string> {
    const changed = new Set([...this.entries.keys(), ...this.held.keys()]);
    this.entries.clear();
    this.held.clear();
    this.runRevisions.clear();
    return changed;
  }

  private set(threadId: string, runId: string, langKey: string, now: number): Set<string> {
    const previous = this.getLangKey(threadId);
    this.entries.set(threadId, { runId, langKey, updatedAt: now });
    return previous === langKey ? new Set() : new Set([threadId]);
  }

  private hold(threadId: string, runId: string, loadCount: number) {
    const entry = this.entries.get(threadId);
    if (!entry || (entry.runId && entry.runId !== runId)) return;

    this.held.set(threadId, { langKey: entry.langKey, loadCount, runRevision: this.runRevisions.get(threadId) });
  }

  private finish(threadId: string, runId?: string): Set<string> {
    if (runId && !this.finishedRunIds.includes(runId)) {
      this.finishedRunIds.push(runId);
      this.finishedRunIds.splice(0, Math.max(0, this.finishedRunIds.length - FINISHED_RUN_LIMIT));
    }

    // A newer run of the thread keeps its status
    const entry = this.entries.get(threadId);
    if (!entry || (runId && entry.runId && entry.runId !== runId)) return new Set();

    this.entries.delete(threadId);
    return this.held.has(threadId) ? new Set() : new Set([threadId]);
  }

  private isRunFinished(runId: string) {
    return this.finishedRunIds.includes(runId);
  }

  private unfinishRun(runId: string) {
    this.finishedRunIds = this.finishedRunIds.filter((id) => id !== runId);
  }
}
