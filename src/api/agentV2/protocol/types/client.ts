import type {
  AgentActionEvent, AgentErrorCodeV2, AgentMessageEndEvent, AgentMessageErrorV2,
  AgentSemanticContentV1 as WireSemanticContent,
} from '../../generated/public';

/** What the client shows in place of semantic content it cannot render */
export interface AgentClientUnsupportedContentV1 {
  kind: 'clientUnsupported';
  schemaVersion: 1;
}

/** Decoded semantic content: the wire notice, or a placeholder for content this client cannot show */
export type AgentDecodedSemanticContentV1 = WireSemanticContent | AgentClientUnsupportedContentV1;

export type AgentAccountType = 'regular' | 'ledger' | 'viewOnly' | 'multisig' | 'unknown';

/** Error codes the client reports; it also reports `client_update_required` itself for a server it cannot read */
export type AgentV2ErrorCode = AgentErrorCodeV2;

/** A message error as the client shows it */
export type AgentV2MessageError = Omit<AgentMessageErrorV2, 'code'> & { code: AgentV2ErrorCode };

/** How a message ended for the client: the server's reason, or an error when its content could not be read */
export type AgentV2FinishReason = AgentMessageEndEvent['finishReason'] | 'error';

/** A live action as the stream delivers it: a proposal with the title the answer gave it */
export type AgentV2LiveAction = AgentActionEvent['action'];
