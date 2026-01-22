import type { Cell, Message } from '@ton/core';
import { beginCell, external, storeMessage } from '@ton/core';

import type { GaslessType } from '../transfer';
import type { TonClient } from './TonClient';
import type { TonWallet } from './tonCore';

import { dieselSendBoc } from './diesel';
import { dieselW5SendRequest } from './w5diesel';

export async function sendExternal(
  client: TonClient,
  wallet: TonWallet,
  message: Cell,
  gaslessType?: GaslessType,
  isWalletInitialized?: boolean,
) {
  const {
    address,
    init,
  } = wallet;

  let neededInit: { data: Cell; code: Cell } | undefined;
  if (init) {
    if (isWalletInitialized === true) {
      neededInit = undefined;
    } else if (isWalletInitialized === false) {
      neededInit = init;
    } else if (!await client.isContractDeployed(address)) {
      neededInit = init;
    }
  }

  const ext = external({
    to: address,
    init: neededInit ? {
      code: neededInit.code,
      data: neededInit.data,
    } : undefined,
    body: message,
  });

  const cell = beginCell()
    .store(storeMessage(ext))
    .endCell();

  const isW5Gasless = gaslessType === 'w5';

  const msgHash = cell.hash().toString('base64');
  const msgHashNormalized = getExternalMsgHashNormalized(ext);
  const bodyMessageHash = message.hash().toString('base64');
  const boc = cell.toBoc().toString('base64');

  let paymentLink;
  if (isW5Gasless) {
    const result = await dieselW5SendRequest(boc);
    paymentLink = result.paymentLink;
  } else if (gaslessType === 'diesel') {
    const result = await dieselSendBoc(boc);
    paymentLink = result.paymentLink;
  } else {
    await client.sendFile(boc);
  }

  return {
    boc,
    msgHash: isW5Gasless ? bodyMessageHash : msgHash,
    msgHashNormalized,
    paymentLink,
  };
}

function getExternalMsgHashNormalized(message: Message): string {
  const cell = beginCell()
    .storeUint(2, 2) // Message type: external-in
    .storeUint(0, 2) // No sender address for external messages
    .storeAddress(message.info.dest) // Store recipient address
    .storeUint(0, 4) // Import fee is always zero for external messages
    .storeBit(false) // No StateInit in this message
    .storeBit(true) // Store the body as a reference
    .storeRef(message.body) // Store the message body
    .endCell();

  return cell.hash().toString('base64');
}
