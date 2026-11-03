import publicWireFixture from '../../../../../tests/fixtures/agentV2/public-wire.v1.json';
import { AgentV2ContractError } from '../wireReader';
import { decodeAgentV2Transcription } from './transcription';

const responseGroup = (publicWireFixture.fixtures as { schema: string; valid: unknown[]; invalid: unknown[] }[])
  .find(({ schema }) => schema === 'AgentTranscriptionResponseV2')!;

describe('Agent V2 transcription decoder', () => {
  it('decodes every valid response the server publishes', () => {
    responseGroup.valid.forEach((value) => {
      expect(decodeAgentV2Transcription(value)).toEqual(value);
    });
  });

  it.each([
    { protocolVersion: 3, outcome: 'transcribed' },
    { protocolVersion: 3, outcome: 'transcribed', text: '' },
    { protocolVersion: 3, outcome: 'transcribed', text: '   ' },
    { protocolVersion: 3, outcome: 'transcribed', text: 'x'.repeat(20_001) },
    { protocolVersion: 3, outcome: 'heard' },
  ])('refuses a transcript the composer cannot take: %j', (value) => {
    expect(() => decodeAgentV2Transcription(value)).toThrow(AgentV2ContractError);
  });

  it('ignores fields a newer server adds', () => {
    expect(decodeAgentV2Transcription({ protocolVersion: 3, outcome: 'transcribed', text: 'Hi', provider: 'x' }))
      .toEqual({ protocolVersion: 3, outcome: 'transcribed', text: 'Hi' });
    expect(decodeAgentV2Transcription({ protocolVersion: 3, outcome: 'no_speech', text: '' }))
      .toEqual({ protocolVersion: 3, outcome: 'no_speech' });
  });
});
