import { secp256k1 } from '@noble/curves/secp256k1';
import { blake2b } from '@noble/hashes/blake2b';
import type { Transaction } from '@scure/btc-signer';
import { CompactSize, VarBytes } from '@scure/btc-signer/script';

import type { ApiNetwork } from '../../types';

const SIGHASH_ALL = 0x01;

const ZIP225_VERSION_GROUP_ID = 0x26a7270a;

/** Blockbook txids are display-order; transparent inputs serialize the reversed (wire) hash. */
export function zcashWirePrevoutHash(blockbookTxid: Uint8Array): Uint8Array {
  if (blockbookTxid.length !== 32) {
    throw new Error('Invalid prevout txid length');
  }

  const hash = new Uint8Array(32);
  for (let i = 0; i < 32; i++) {
    hash[i] = blockbookTxid[31 - i];
  }

  return hash;
}

type ZcashTxInput = {
  hash: Uint8Array;
  index: number;
  sequence: number;
  script: Uint8Array;
  value: bigint;
  prevOutScript: Uint8Array;
};

type ZcashTxOutput = {
  value: bigint;
  script: Uint8Array;
};

type ZcashTx = {
  version: number;
  overwintered: number;
  versionGroupId: number;
  consensusBranchId: number;
  locktime: number;
  expiryHeight: number;
  ins: ZcashTxInput[];
  outs: ZcashTxOutput[];
};

class BufferWriter {
  private chunks: Uint8Array[] = [];

  writeUInt8(value: number) {
    this.chunks.push(Uint8Array.of(value));
  }

  writeUInt32(value: number) {
    const buf = new Uint8Array(4);
    const view = new DataView(buf.buffer);
    view.setUint32(0, value, true);
    this.chunks.push(buf);
  }

  writeInt32(value: number) {
    const buf = new Uint8Array(4);
    const view = new DataView(buf.buffer);
    view.setInt32(0, value, true);
    this.chunks.push(buf);
  }

  writeUInt64(value: bigint) {
    const buf = new Uint8Array(8);
    const view = new DataView(buf.buffer);
    view.setBigUint64(0, value, true);
    this.chunks.push(buf);
  }

  writeInt64(value: bigint) {
    const buf = new Uint8Array(8);
    const view = new DataView(buf.buffer);
    view.setBigInt64(0, value, true);
    this.chunks.push(buf);
  }

  writeSlice(data: Uint8Array) {
    this.chunks.push(data);
  }

  writeVarSlice(data: Uint8Array) {
    this.chunks.push(VarBytes.encode(data));
  }

  writeVarInt(value: number) {
    this.chunks.push(CompactSize.encode(BigInt(value)));
  }

  end(): Uint8Array {
    const total = this.chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const out = new Uint8Array(total);
    let offset = 0;

    for (const chunk of this.chunks) {
      out.set(chunk, offset);
      offset += chunk.length;
    }

    return out;
  }
}

function zcashPersonalization(tag: string, branchId?: number): Uint8Array {
  const personalization = new Uint8Array(16);
  const tagBytes = new TextEncoder().encode(tag);
  personalization.set(tagBytes.subarray(0, Math.min(tagBytes.length, 16)));

  if (branchId !== undefined) {
    const view = new DataView(personalization.buffer);
    view.setUint32(12, branchId, true);
  }

  return personalization;
}

function zcashBlake2b(data: Uint8Array, personalization: Uint8Array): Uint8Array {
  return blake2b(data, { dkLen: 32, personalization });
}

function getHeaderDigest(tx: ZcashTx): Uint8Array {
  const writer = new BufferWriter();
  const header = tx.version | (tx.overwintered << 31);
  writer.writeInt32(header);
  writer.writeUInt32(tx.versionGroupId);
  writer.writeUInt32(tx.consensusBranchId);
  writer.writeUInt32(tx.locktime);
  writer.writeUInt32(tx.expiryHeight);

  return zcashBlake2b(writer.end(), zcashPersonalization('ZTxIdHeadersHash'));
}

function getPrevoutsDigest(ins: ZcashTxInput[], sigParams?: SignatureParams): Uint8Array {
  if (sigParams && (sigParams.hashType & 0x80)) {
    return getPrevoutsDigest([]);
  }

  const writer = new BufferWriter();
  ins.forEach((input) => {
    writer.writeSlice(input.hash);
    writer.writeUInt32(input.index);
  });

  return zcashBlake2b(writer.end(), zcashPersonalization('ZTxIdPrevoutHash'));
}

function getSequenceDigest(ins: ZcashTxInput[], sigParams?: SignatureParams): Uint8Array {
  if (sigParams) {
    const hashType = sigParams.hashType;
    if (
      (hashType & 0x80)
      || (hashType & 0x1f) === 0x03
      || (hashType & 0x1f) === 0x02
    ) {
      return getSequenceDigest([]);
    }
  }

  const writer = new BufferWriter();
  ins.forEach((input) => {
    writer.writeUInt32(input.sequence);
  });

  return zcashBlake2b(writer.end(), zcashPersonalization('ZTxIdSequencHash'));
}

function getOutputsDigest(outs: ZcashTxOutput[], sigParams?: SignatureParams): Uint8Array {
  if (sigParams) {
    const hashType = sigParams.hashType & 0x1f;

    if (hashType === 0x03) {
      const inIndex = sigParams.inIndex;
      if (inIndex === undefined || outs[inIndex] === undefined) {
        return zcashBlake2b(new Uint8Array(0), zcashPersonalization('ZTxIdOutputsHash'));
      }

      return getOutputsDigest([outs[inIndex]]);
    }

    if (hashType === 0x02) {
      return getOutputsDigest([]);
    }
  }

  const writer = new BufferWriter();
  outs.forEach((output) => {
    writer.writeUInt64(output.value);
    writer.writeVarSlice(output.script);
  });

  return zcashBlake2b(writer.end(), zcashPersonalization('ZTxIdOutputsHash'));
}

type SignatureParams = {
  inIndex: number;
  hashType: number;
};

function getAmountsDigest(ins: ZcashTxInput[], sigParams?: SignatureParams): Uint8Array {
  if (sigParams && (sigParams.hashType & 0x80)) {
    return zcashBlake2b(new Uint8Array(0), zcashPersonalization('ZTxTrAmountsHash'));
  }

  const writer = new BufferWriter();
  ins.forEach((input) => {
    writer.writeInt64(input.value);
  });

  return zcashBlake2b(writer.end(), zcashPersonalization('ZTxTrAmountsHash'));
}

function getScriptsDigest(ins: ZcashTxInput[], sigParams?: SignatureParams): Uint8Array {
  if (sigParams && (sigParams.hashType & 0x80)) {
    return zcashBlake2b(new Uint8Array(0), zcashPersonalization('ZTxTrScriptsHash'));
  }

  const writer = new BufferWriter();
  ins.forEach((input) => {
    writer.writeVarSlice(input.prevOutScript);
  });

  return zcashBlake2b(writer.end(), zcashPersonalization('ZTxTrScriptsHash'));
}

/** ZIP-244 S.2 transparent signature digest (not the T.2 txid transparent digest). */
function getTxinSigDigest(input: ZcashTxInput): Uint8Array {
  const writer = new BufferWriter();
  writer.writeSlice(input.hash);
  writer.writeUInt32(input.index);
  writer.writeInt64(input.value);
  writer.writeVarSlice(input.prevOutScript);
  writer.writeUInt32(input.sequence);

  return zcashBlake2b(writer.end(), zcashPersonalization('Zcash___TxInHash'));
}

function getTransparentSigDigest(tx: ZcashTx, sigParams: SignatureParams): Uint8Array {
  const writer = new BufferWriter();
  writer.writeUInt8(sigParams.hashType);
  writer.writeSlice(getPrevoutsDigest(tx.ins, sigParams));
  writer.writeSlice(getAmountsDigest(tx.ins, sigParams));
  writer.writeSlice(getScriptsDigest(tx.ins, sigParams));
  writer.writeSlice(getSequenceDigest(tx.ins, sigParams));
  writer.writeSlice(getOutputsDigest(tx.outs, sigParams));
  writer.writeSlice(getTxinSigDigest(tx.ins[sigParams.inIndex]));

  return zcashBlake2b(writer.end(), zcashPersonalization('ZTxIdTranspaHash'));
}

function getSaplingDigest(): Uint8Array {
  return zcashBlake2b(new Uint8Array(0), zcashPersonalization('ZTxIdSaplingHash'));
}

function getOrchardDigest(): Uint8Array {
  return zcashBlake2b(new Uint8Array(0), zcashPersonalization('ZTxIdOrchardHash'));
}

function getSignatureDigest(tx: ZcashTx, sigParams: SignatureParams): Uint8Array {
  const writer = new BufferWriter();
  writer.writeSlice(getHeaderDigest(tx));
  writer.writeSlice(getTransparentSigDigest(tx, sigParams));
  writer.writeSlice(getSaplingDigest());
  writer.writeSlice(getOrchardDigest());

  return zcashBlake2b(
    writer.end(),
    zcashPersonalization('ZcashTxHash_', tx.consensusBranchId),
  );
}

function serializeZcashV5(tx: ZcashTx): Uint8Array {
  const writer = new BufferWriter();
  const header = tx.version | (tx.overwintered << 31);

  writer.writeInt32(header);
  writer.writeUInt32(tx.versionGroupId);
  writer.writeUInt32(tx.consensusBranchId);
  writer.writeUInt32(tx.locktime);
  writer.writeUInt32(tx.expiryHeight);

  writer.writeVarInt(tx.ins.length);
  tx.ins.forEach((input) => {
    writer.writeSlice(input.hash);
    writer.writeUInt32(input.index);
    writer.writeVarSlice(input.script);
    writer.writeUInt32(input.sequence);
  });

  writer.writeVarInt(tx.outs.length);
  tx.outs.forEach((output) => {
    writer.writeUInt64(output.value);
    writer.writeVarSlice(output.script);
  });

  writer.writeVarInt(0);
  writer.writeVarInt(0);
  writer.writeUInt8(0);

  return writer.end();
}

function concatScriptSig(signature: Uint8Array, publicKey: Uint8Array): Uint8Array {
  const sigWithHashType = new Uint8Array(signature.length + 1);
  sigWithHashType.set(signature);
  sigWithHashType[signature.length] = SIGHASH_ALL;

  const sigPush = VarBytes.encode(sigWithHashType);
  const keyPush = VarBytes.encode(publicKey);
  const script = new Uint8Array(sigPush.length + keyPush.length);
  script.set(sigPush);
  script.set(keyPush, sigPush.length);

  return script;
}

function transactionFromBtcSigner(
  btcTx: Transaction,
  network: ApiNetwork,
  expiryHeight: number,
  consensusBranchId: number,
): ZcashTx {
  const ins: ZcashTxInput[] = [];
  const outs: ZcashTxOutput[] = [];

  for (let i = 0; i < btcTx.inputsLength; i++) {
    const input = btcTx.getInput(i);
    if (!input.txid || input.index === undefined) {
      throw new Error('Zcash input is missing outpoint');
    }

    const witnessUtxo = input.witnessUtxo;
    if (!witnessUtxo?.script || witnessUtxo.amount === undefined) {
      throw new Error('Zcash input is missing witnessUtxo');
    }

    ins.push({
      hash: zcashWirePrevoutHash(input.txid),
      index: input.index,
      sequence: input.sequence ?? 0xffffffff,
      script: new Uint8Array(0),
      value: witnessUtxo.amount,
      prevOutScript: witnessUtxo.script,
    });
  }

  for (let i = 0; i < btcTx.outputsLength; i++) {
    const output = btcTx.getOutput(i);
    if (!output.script) {
      throw new Error('Zcash output is missing script');
    }

    outs.push({
      value: output.amount ?? 0n,
      script: output.script,
    });
  }

  return {
    version: 5,
    overwintered: 1,
    versionGroupId: ZIP225_VERSION_GROUP_ID,
    consensusBranchId,
    locktime: 0,
    expiryHeight,
    ins,
    outs,
  };
}

export function signZcashTransaction(
  btcTx: Transaction,
  network: ApiNetwork,
  privateKey: Uint8Array,
  expiryHeight: number,
  consensusBranchId: number,
): Uint8Array {
  const publicKey = secp256k1.getPublicKey(privateKey, true);
  const tx = transactionFromBtcSigner(btcTx, network, expiryHeight, consensusBranchId);

  for (let i = 0; i < tx.ins.length; i++) {
    const digest = getSignatureDigest(tx, {
      inIndex: i,
      hashType: SIGHASH_ALL,
    });
    const signature = secp256k1.sign(digest, privateKey, { lowS: true }).toDERRawBytes();
    tx.ins[i].script = concatScriptSig(signature, publicKey);
  }

  return serializeZcashV5(tx);
}

export function bytesToHexLower(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}
