import type {
  AgentWalletSnapshotAckV1, AgentWalletSnapshotRefV1, AgentWalletSnapshotV1,
} from './protocol/types';
import type { AgentV2WalletSession } from './walletSession';

import { pauseWithAbortSignal } from '../../util/abortSignal';
import { isRetryableAgentV2RunError } from './errors';
import { AgentV2HttpError } from './identity';
import { projectWalletSnapshot } from './walletSnapshot';

// Local metadata is revalidated before the server's 30-second wallet-read freshness window expires
const SNAPSHOT_REVALIDATION_INTERVAL_MS = 20_000;

interface Dependencies {
  session: AgentV2WalletSession;
  now: () => number;
  instanceId: string | (() => string);
  send: (snapshot: AgentWalletSnapshotV1, signal: AbortSignal) => Promise<AgentWalletSnapshotAckV1>;
}

export class AgentV2WalletSnapshotSync {
  private isActive = false;
  private revision = 0;
  private instanceId?: string;
  private current?: AgentWalletSnapshotV1;
  private fingerprint?: string;
  private acknowledged?: AgentWalletSnapshotRefV1;
  private controller?: AbortController;
  private pending?: AgentWalletSnapshotV1;
  private uploadingRevision?: number;
  private rejectedFingerprint?: string;
  private revalidationTimer?: ReturnType<typeof setTimeout>;
  private nextRevalidationAt = 0;

  constructor(private readonly dependencies: Dependencies) {}

  setActive(isActive: boolean) {
    if (isActive === this.isActive) return;
    this.isActive = isActive;
    if (isActive) {
      this.acknowledged = undefined;
      this.rejectedFingerprint = undefined;
      this.refresh();
    } else {
      clearTimeout(this.revalidationTimer);
      this.revalidationTimer = undefined;
      this.pending = undefined;
      this.controller?.abort();
    }
  }

  reset() {
    this.setActive(false);
    this.current = undefined;
    this.fingerprint = undefined;
    this.rejectedFingerprint = undefined;
    this.acknowledged = undefined;
    this.nextRevalidationAt = 0;
  }

  refresh() {
    const now = this.dependencies.now();
    let value: AgentWalletSnapshotV1 | undefined;
    try {
      this.instanceId ??= typeof this.dependencies.instanceId === 'function'
        ? this.dependencies.instanceId() : this.dependencies.instanceId;
      value = projectWalletSnapshot(this.dependencies.session, this.instanceId,
        this.revision + 1, now);
    } catch {
      value = undefined;
    }
    if (!value) {
      this.current = undefined;
      this.fingerprint = undefined;
      this.pending = undefined;
      this.acknowledged = undefined;
      this.controller?.abort();
      return;
    }
    const fingerprint = snapshotFingerprint(value);
    const shouldRevalidate = now >= this.nextRevalidationAt;
    if (fingerprint !== this.fingerprint || shouldRevalidate) {
      if (!shouldRevalidate && this.current
        && sectionFingerprint(this.current.contacts) === sectionFingerprint(value.contacts)) {
        value.contacts.asOf = this.current.contacts.asOf;
      }
      this.revision += 1;
      this.fingerprint = fingerprint;
      this.current = value;
      if (shouldRevalidate) this.nextRevalidationAt = now + SNAPSHOT_REVALIDATION_INTERVAL_MS;
    }
    if (this.isActive && this.current && this.fingerprint !== this.rejectedFingerprint
      && (this.controller?.signal.aborted || this.uploadingRevision !== this.current.snapshotRevision)
      && this.acknowledged?.snapshotRevision !== this.current.snapshotRevision) {
      this.pending = this.current;
      void this.drain();
    }
    if (this.isActive && this.revalidationTimer === undefined) {
      this.revalidationTimer = setTimeout(() => {
        this.revalidationTimer = undefined;
        this.refresh();
      }, Math.max(0, this.nextRevalidationAt - now));
    }
  }

  forRun(): { walletSnapshotRef?: AgentWalletSnapshotRefV1 } {
    this.refresh();
    if (!this.current) return {};
    return this.acknowledged?.snapshotRevision === this.current.snapshotRevision
      ? { walletSnapshotRef: this.acknowledged } : {};
  }

  private async drain() {
    if (this.controller || !this.isActive || !this.pending) return;
    if (this.pending.snapshotRevision === this.acknowledged?.snapshotRevision
      || snapshotFingerprint(this.pending) === this.rejectedFingerprint) {
      this.pending = undefined;
      return;
    }
    const controller = new AbortController();
    this.controller = controller;
    const value = this.pending;
    this.uploadingRevision = value.snapshotRevision;
    this.pending = undefined;
    try {
      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          const { snapshotRef } = await this.dependencies.send(value, controller.signal);
          if (!controller.signal.aborted && sameRef(snapshotRef, value)) this.acknowledged = snapshotRef;
          break;
        } catch (error) {
          if (!controller.signal.aborted && !isRetryableAgentV2RunError(error)
            && !(error instanceof AgentV2HttpError && error.status === 429)) {
            this.rejectedFingerprint = snapshotFingerprint(value);
            break;
          }
          if (controller.signal.aborted || this.pending || attempt === 2) break;
          await pauseWithAbortSignal(250 * 2 ** attempt, controller.signal);
        }
      }
    } catch {
      // Closing the chat or resetting the SDK cancels the pending retry.
    } finally {
      if (this.controller === controller) {
        this.controller = undefined;
        this.uploadingRevision = undefined;
      }
      if (this.pending) void this.drain();
    }
  }
}

function sameRef(left: AgentWalletSnapshotRefV1, right: AgentWalletSnapshotRefV1) {
  return left.instanceId === right.instanceId && left.sessionId === right.sessionId
    && left.revision === right.revision && left.snapshotRevision === right.snapshotRevision;
}

function sectionFingerprint(value: unknown) {
  return JSON.stringify(value, (key, entry: unknown) => key === 'asOf' ? undefined : entry);
}

function snapshotFingerprint(value: AgentWalletSnapshotV1) {
  return JSON.stringify(value, (key, entry: unknown) => (
    key === 'capturedAt' || key === 'asOf' || key === 'snapshotRevision' ? undefined : entry
  ));
}
