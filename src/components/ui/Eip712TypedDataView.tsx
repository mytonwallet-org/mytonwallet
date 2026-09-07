import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { EvmEip712SignDataPayload } from '../../api/dappProtocols/adapters/walletConnect/types';

import useLang from '../../hooks/useLang';

import {
  SignDataFieldRow,
  SignDataLabel,
  SignDataPayloadField,
  SignDataStruct,
  SignDataStructuredBlock,
  signDataStructuredStyles as styles,
} from './SignDataStructuredView';

const MAX_EIP712_DEPTH = 32;

type Eip712TypeDefinitions = EvmEip712SignDataPayload['types'];

export type Eip712TypedDataViewProps = Pick<EvmEip712SignDataPayload, 'domain' | 'types' | 'primaryType' | 'message'>;

function parseEip712ArrayType(type: string): { elementType: string } | undefined {
  const lastOpen = type.lastIndexOf('[');
  if (lastOpen === -1 || !type.endsWith(']')) return undefined;
  const suffix = type.slice(lastOpen);
  if (!/^\[\d*\]$/.test(suffix)) return undefined;
  return { elementType: type.slice(0, lastOpen) };
}

function isEip712PrimitiveType(type: string): boolean {
  if (type === 'bytes' || type === 'string') return true;
  if (type === 'address' || type === 'bool') return true;
  if (/^bytes([1-9]|[12][0-9]|3[0-2])$/.test(type)) return true;
  if (/^u?int(\d{1,3})?$/.test(type)) return true;
  return false;
}

function formatEip712Scalar(value: unknown): string {
  if (value === undefined) return '';
  if (typeof value === 'object' && !value) return '';
  if (typeof value === 'bigint') return value.toString();
  if (typeof value === 'boolean' || typeof value === 'number') return String(value);
  if (typeof value === 'string') return value;
  return JSON.stringify(value);
}

function renderEip712LeafUnknown(value: unknown): TeactNode {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return (
      <SignDataStruct>
        {Object.keys(value as Record<string, unknown>).sort().map((key) => (
          <SignDataFieldRow key={key} name={key}>
            {renderEip712LeafUnknown((value as Record<string, unknown>)[key])}
          </SignDataFieldRow>
        ))}
      </SignDataStruct>
    );
  }
  if (Array.isArray(value)) {
    return (
      <div className={styles.array}>
        {value.map((item, index) => (
          <div key={index} className={styles.arrayItem}>
            <span className={styles.arrayIndex}>{`[${index}]`}</span>
            <div className={styles.fieldValue}>{renderEip712LeafUnknown(item)}</div>
          </div>
        ))}
      </div>
    );
  }
  return formatEip712Scalar(value);
}

function renderEip712Value(
  value: unknown,
  solidityType: string,
  types: Eip712TypeDefinitions,
  depth: number,
  keyPrefix: string,
): TeactNode {
  if (depth > MAX_EIP712_DEPTH) {
    return formatEip712Scalar(value);
  }

  const arrayInfo = parseEip712ArrayType(solidityType);
  if (arrayInfo) {
    const { elementType } = arrayInfo;
    const items = Array.isArray(value) ? value : [];

    return (
      <div className={styles.array}>
        {items.map((item, index) => (
          <div key={`${keyPrefix}-${index}`} className={styles.arrayItem}>
            <span className={styles.arrayIndex}>{`[${index}]`}</span>
            <div className={styles.fieldValue}>
              {renderEip712Value(item, elementType, types, depth + 1, `${keyPrefix}-${index}`)}
            </div>
          </div>
        ))}
      </div>
    );
  }

  const structFields = types[solidityType];
  if (structFields?.length && value && typeof value === 'object' && !Array.isArray(value)) {
    return renderEip712Struct(value as Record<string, unknown>, solidityType, types, depth, keyPrefix);
  }

  if (isEip712PrimitiveType(solidityType)) {
    return formatEip712Scalar(value);
  }

  if (value && typeof value === 'object') {
    return renderEip712LeafUnknown(value);
  }

  return formatEip712Scalar(value);
}

function renderEip712Struct(
  obj: Record<string, unknown>,
  typeName: string,
  types: Eip712TypeDefinitions,
  depth: number,
  keyPrefix: string,
): TeactNode {
  const fields = types[typeName];
  if (!fields?.length) {
    return renderEip712LeafUnknown(obj);
  }

  return (
    <SignDataStruct depth={depth}>
      {fields.map((field) => (
        <SignDataFieldRow key={`${keyPrefix}-${field.name}`} name={field.name}>
          {renderEip712Value(obj[field.name], field.type, types, depth + 1, `${keyPrefix}-${field.name}`)}
        </SignDataFieldRow>
      ))}
    </SignDataStruct>
  );
}

function renderEip712DomainBlock(
  domain: Record<string, unknown>,
  types: Eip712TypeDefinitions,
): TeactNode {
  if (types.EIP712Domain?.length) {
    return renderEip712Struct(domain, 'EIP712Domain', types, 0, 'domain');
  }
  return renderEip712LeafUnknown(domain);
}

function renderEip712MessageBlock(
  message: Record<string, unknown>,
  primaryType: string,
  types: Eip712TypeDefinitions,
): TeactNode {
  if (types[primaryType]?.length) {
    return renderEip712Struct(message, primaryType, types, 0, 'message');
  }
  return renderEip712LeafUnknown(message);
}

function Eip712TypedDataView({
  domain, types, primaryType, message,
}: Eip712TypedDataViewProps) {
  const lang = useLang();

  return (
    <>
      <SignDataLabel>{lang('EIP-712 typed data')}</SignDataLabel>
      <SignDataLabel>{lang('Primary type')}</SignDataLabel>
      <SignDataPayloadField isText>
        {primaryType}
      </SignDataPayloadField>

      <SignDataStructuredBlock label={lang('EIP-712 domain')} isExpanded>
        {renderEip712DomainBlock(domain, types)}
      </SignDataStructuredBlock>

      <SignDataStructuredBlock label={lang('Message')} isExpanded isText>
        {renderEip712MessageBlock(message, primaryType, types)}
      </SignDataStructuredBlock>
    </>
  );
}

export default memo(Eip712TypedDataView);
