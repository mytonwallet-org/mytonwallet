import type { AgentV2StreamItem } from './ndjson';
import type {
  AgentAnswerLinkV1,
  AgentAnswerTableReferenceV1,
  AgentAnswerTableV1,
  AgentMessageEndEvent,
  AgentSemanticContentV1,
  AgentStreamEventV2,
  AgentV2LiveAction,
} from './protocol/types';

import { canPlaceAnswerLink, MAX_MESSAGE_LINKS } from './protocol/decoders/answerLinks';
import { AgentV2StreamProtocolError } from './ndjson';

interface PendingStructuredOutput {
  messageId: string;
  actions: AgentV2LiveAction[];
  semanticContent?: AgentSemanticContentV1;
  isInvalid: boolean;
}

export class AgentV2StreamMessage {
  private messageId?: string;
  private textLength = 0;
  private isContentFinished = false;
  private answerTables: AgentAnswerTableV1[] = [];
  private answerTableReferences: AgentAnswerTableReferenceV1[] = [];
  private answerLinks: AgentAnswerLinkV1[] = [];
  private pending?: PendingStructuredOutput;

  get id() {
    return this.messageId;
  }

  get tables() {
    return this.answerTables;
  }

  get tableReferences() {
    return this.answerTableReferences;
  }

  get links() {
    return this.answerLinks;
  }

  accept(event: AgentV2StreamItem) {
    switch (event.type) {
      case 'message_start':
        this.messageId = event.messageId;
        this.textLength = 0;
        this.isContentFinished = false;
        this.answerTables = [];
        this.answerTableReferences = [];
        this.answerLinks = [];
        break;
      case 'text_delta':
        this.invalidateStructuredOutput();
        this.textLength += event.delta.length;
        break;
      case 'message_end':
        if (event.finishReason === 'complete' || event.finishReason === 'tool_unavailable') {
          this.validateCompletedTables();
        }
        break;
      case 'message_content_end':
        this.validateCompletedTables();
        this.isContentFinished = true;
        break;
      case 'table_data':
      case 'table_reference':
        this.acceptTable(event);
        break;
      case 'text_link':
        this.acceptLink(event);
        break;
      case 'action': {
        const pending = this.getPendingStructuredOutput(event.messageId);
        if (pending.isInvalid) break;
        if (pending.actions.some(({ id }) => id === event.action.id)) {
          this.invalidateStructuredOutput();
          break;
        }
        pending.actions.push(event.action);
        break;
      }
      case 'semantic_content': {
        const pending = this.getPendingStructuredOutput(event.messageId);
        if (pending.isInvalid) break;
        if (pending.semanticContent) {
          this.invalidateStructuredOutput();
          break;
        }
        pending.semanticContent = event.content;
        break;
      }
      case 'tool_call':
      case 'unsupported_tool_call':
      case 'tool_status':
        this.invalidateStructuredOutput();
        break;
      case 'error':
        this.pending = undefined;
        break;
    }
  }

  finish(messageId: string, reason: AgentMessageEndEvent['finishReason']) {
    const pending = this.pending;
    this.pending = undefined;
    if (!pending || pending.isInvalid || pending.messageId !== messageId || this.messageId !== messageId
      || (reason !== 'complete' && reason !== 'tool_unavailable')) return undefined;
    return {
      semanticContent: pending.semanticContent,
      actions: reason === 'complete' ? pending.actions : [],
    };
  }

  private validateCompletedTables() {
    if (this.answerTableReferences.some((reference) => reference.textOffset > this.textLength)) {
      throw new AgentV2StreamProtocolError('Answer table reference exceeds completed text');
    }
  }

  private acceptTable(event: Extract<AgentStreamEventV2, { type: 'table_data' | 'table_reference' }>) {
    if (this.messageId !== event.messageId || this.isContentFinished) {
      throw new AgentV2StreamProtocolError('Invalid answer table message binding');
    }
    if (event.type === 'table_data') {
      if (this.answerTables.length >= 16 || this.answerTables.some(({ id }) => id === event.table.id)) {
        throw new AgentV2StreamProtocolError('Duplicate or excessive answer table');
      }
      this.answerTables = [...this.answerTables, event.table];
    } else {
      const reference = event.reference;
      if (!this.answerTables.some(({ id }) => id === reference.tableId)
        || this.answerTableReferences.some(({ tableId }) => tableId === reference.tableId)
        || reference.textOffset < (this.answerTableReferences.at(-1)?.textOffset ?? 0)) {
        throw new AgentV2StreamProtocolError('Unbound answer table reference');
      }
      this.answerTableReferences = [...this.answerTableReferences, reference];
    }
  }

  /**
   * Keeps a link that follows the previous one and does not contain a placed table. Its label arrives with
   * later text; a link the text never covers is not shown. A link never fails the message.
   */
  private acceptLink(event: Extract<AgentStreamEventV2, { type: 'text_link' }>) {
    if (this.messageId !== event.messageId || this.isContentFinished
      || this.answerLinks.length >= MAX_MESSAGE_LINKS
      || !canPlaceAnswerLink(event.link, this.answerLinks.at(-1), Number.POSITIVE_INFINITY,
        this.answerTableReferences.map(({ textOffset }) => textOffset))) return;
    this.answerLinks = [...this.answerLinks, event.link];
  }

  private getPendingStructuredOutput(messageId: string) {
    if (!this.pending) {
      this.pending = {
        messageId,
        actions: [],
        isInvalid: this.messageId !== messageId,
      };
    } else if (this.pending.messageId !== messageId) {
      this.invalidateStructuredOutput();
    }
    return this.pending;
  }

  private invalidateStructuredOutput() {
    if (!this.pending) return;
    this.pending.actions.length = 0;
    delete this.pending.semanticContent;
    this.pending.isInvalid = true;
  }
}
