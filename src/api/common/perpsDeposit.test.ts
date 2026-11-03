import type { ApiPerpsCctpDeposit } from '../types';

import depositFixture from '../../../tests/fixtures/perpsDeposit.json';
import { assertPerpsCctpDepositIntegrity } from './perpsDeposit';

const WALLET = depositFixture.permitData.values.from;
const OTHER = '0x2222222222222222222222222222222222222222';
const fixture = () => JSON.parse(JSON.stringify(depositFixture)) as ApiPerpsCctpDeposit;

function liveIncreaseDeposit() {
  const deposit = fixture();
  deposit.amountUsdc = '10.317612';
  deposit.permitData.values.value = deposit.burnCall.amount = '10317612';
  deposit.creditedAmountUsdc = String(Number(deposit.amountUsdc) - Number(deposit.feeUsdc));
  return deposit;
}

test('accepts the backend CCTP deposit format for the exact reviewed USDC amount', () => {
  expect(() => assertPerpsCctpDepositIntegrity(fixture(), WALLET, '50.2')).not.toThrow();
});

test('accepts the live $40 BTC increase with floating-point noise in credited metadata', () => {
  const deposit = liveIncreaseDeposit();
  expect(deposit.creditedAmountUsdc).toBe('10.117612000000001');
  expect(() => assertPerpsCctpDepositIntegrity(deposit, WALLET, '10.317612')).not.toThrow();
  deposit.creditedAmountUsdc = '10.117611999999999';
  expect(() => assertPerpsCctpDepositIntegrity(deposit, WALLET, '10.317612')).not.toThrow();
});

test.each(['10.117611', '10.117613'])('rejects credited metadata changed by one USDC base unit (%s)', (credit) => {
  const deposit = liveIncreaseDeposit();
  deposit.creditedAmountUsdc = credit;
  expect(() => assertPerpsCctpDepositIntegrity(deposit, WALLET, '10.317612')).toThrow('PerpsReviewChanged');
});

test.each(['authorization', 'burn'])('keeps %s amounts exact despite floating-point metadata', (field) => {
  const deposit = liveIncreaseDeposit();
  if (field === 'authorization') deposit.permitData.values.value = '10317613';
  else deposit.burnCall.amount = '10317613';
  expect(() => assertPerpsCctpDepositIntegrity(deposit, WALLET, '10.317612')).toThrow('PerpsReviewChanged');
});

test.each<[string, (deposit: ApiPerpsCctpDeposit) => void]>([
  ['advertised amount', (d) => { d.amountUsdc = '500'; }],
  ['authorization amount', (d) => { d.permitData.values.value = '500000000'; }],
  ['burn amount', (d) => { d.burnCall.amount = '500000000'; }],
  ['both signed and burned amounts', (d) => {
    d.permitData.values.value = '500000000';
    d.burnCall.amount = '500000000';
  }],
  ['wallet', (d) => { d.permitData.values.from = OTHER; }],
  ['authorization recipient', (d) => { d.permitData.values.to = OTHER; }],
  ['token contract', (d) => { d.permitData.domain.verifyingContract = OTHER; }],
  ['token domain name', (d) => { d.permitData.domain.name = 'Other Coin'; }],
  ['token domain version', (d) => { d.permitData.domain.version = '1'; }],
  ['signing chain', (d) => { d.permitData.domain.chainId = 1; }],
  ['authorization action', (d) => {
    d.permitData.types = { TransferWithAuthorization: d.permitData.types.ReceiveWithAuthorization };
  }],
  ['authorization field type', (d) => {
    (d.permitData.types.ReceiveWithAuthorization as { type: string }[])[2].type = 'uint128';
  }],
  ['authorization nonce', (d) => { d.permitData.values.nonce = '0x01'; }],
  ['destination domain', (d) => { d.burnCall.destinationDomain = 3; }],
  ['mint recipient', (d) => { d.burnCall.mintRecipient = `0x${'22'.repeat(32)}`; }],
  ['destination caller', (d) => { d.burnCall.destinationCaller = `0x${'22'.repeat(32)}`; }],
  ['forwarding recipient', (d) => {
    d.burnCall.hookData = d.burnCall.hookData.replace(WALLET.slice(2), OTHER.slice(2));
  }],
  ['destination DEX', (d) => { d.burnCall.hookData = `${d.burnCall.hookData.slice(0, -8)}ffffffff`; }],
  ['maximum bridge fee', (d) => { d.burnCall.maxFee = '2000000'; }],
  ['finality', (d) => { d.burnCall.minFinalityThreshold = 0; }],
  ['credited amount', (d) => { d.creditedAmountUsdc = '500'; }],
  ['fee', (d) => { d.feeUsdc = '2'; }],
])('rejects tampered %s before authorization', (_, tamper) => {
  const deposit = fixture();
  tamper(deposit);
  expect(() => assertPerpsCctpDepositIntegrity(deposit, WALLET, '50.2')).toThrow('PerpsReviewChanged');
});
