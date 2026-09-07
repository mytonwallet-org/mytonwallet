import { Cell, type Slice } from '@ton/core';
import type { ParsedCell } from '@ton-community/tlb-runtime';
import * as tlbRuntime from '@ton-community/tlb-runtime';

const MAX_FIELD_COUNT = 100;
const MAX_FIELD_DEPTH = 8;
const MAX_TLB_SCHEMA_LENGTH = 16 * 1024;
const MAX_TLB_DECLARATION_COUNT = 128;
const MAX_TLB_FIELD_COUNT = 256;
const MAX_CELL_BOC_BYTES = 64 * 1024;
const MAX_CELL_BASE64_LENGTH = Math.ceil(MAX_CELL_BOC_BYTES / 3) * 4 + 4;

export interface ApiParsedSignDataCellField {
  label: string;
  value: string;
  depth: number;
  isMuted?: boolean;
}

export interface ApiParsedSignDataCellPreview {
  title: string;
  hash?: string;
  bits: number;
  refs: number;
  fields: ApiParsedSignDataCellField[];
  error?: string;
  isParsed: boolean;
}

interface CellLike {
  bits?: { length?: number };
  refs?: unknown[];
  hash?: () => Buffer | Uint8Array;
}

type VarUInteger16FieldsByKind = ReadonlyMap<string, ReadonlySet<string>>;

interface RuntimeField {
  name: string;
  fieldType: {
    kind?: string;
    n?: RuntimeMathExpression;
    signed?: boolean;
  };
}

interface RuntimeConstructor {
  name: string;
  fields: RuntimeField[];
}

interface RuntimeType {
  name: string;
  constructors: RuntimeConstructor[];
}

interface RuntimeMathExpression {
  n?: number;
  operation?: string;
  value?: RuntimeMathExpression;
  left?: RuntimeMathExpression;
  right?: RuntimeMathExpression;
}

interface RuntimeWithNormalizedTypes {
  types?: Map<string, RuntimeType>;
  deserializeByTypeName?: (
    typeName: string,
    slice: Slice,
  ) => { success: true; value: ParsedCell } | { success: false; error: Error };
}

export function buildSignDataCellPreview(cellBase64: string, schema?: string): ApiParsedSignDataCellPreview {
  const cellSizeError = getCellSizeLimitError(cellBase64);
  if (cellSizeError) {
    return {
      title: 'TON Cell',
      bits: 0,
      refs: 0,
      fields: [getRawPayloadField(cellBase64)],
      error: cellSizeError,
      isParsed: false,
    };
  }

  let cell: Cell;
  try {
    cell = Cell.fromBase64(cellBase64);
  } catch (err) {
    return {
      title: 'TON Cell',
      bits: 0,
      refs: 0,
      fields: [getRawPayloadField(cellBase64)],
      error: getErrorMessage(err, 'Failed to parse cell payload.'),
      isParsed: false,
    };
  }

  const basePreview = {
    hash: cell.hash().toString('hex'),
    bits: cell.bits.length,
    refs: cell.refs.length,
  };

  if (!schema?.trim()) {
    return {
      title: 'TON Cell',
      ...basePreview,
      fields: [getRawPayloadField(cellBase64)],
      error: 'Missing TL-B schema.',
      isParsed: false,
    };
  }

  const schemaLimitError = getSchemaLimitError(schema);
  if (schemaLimitError) {
    return {
      title: 'TON Cell',
      ...basePreview,
      fields: [getRawPayloadField(cellBase64)],
      error: schemaLimitError,
      isParsed: false,
    };
  }

  try {
    const runtime = tlbRuntime.parseTLB(schema);
    const rootType = getRootTypeName(runtime);
    const varUInteger16FieldsByKind = getVarUInteger16FieldsByKind(runtime);
    const result = deserializeRootType(runtime, rootType, cell.beginParse());

    if (!result.success) {
      return {
        title: 'TON Cell',
        ...basePreview,
        fields: [getRawPayloadField(cellBase64)],
        error: result.error.message,
        isParsed: false,
      };
    }

    if (rootType && !isRootKind(result.value, rootType)) {
      return {
        title: 'TON Cell',
        ...basePreview,
        fields: [getRawPayloadField(cellBase64)],
        error: `Parsed constructor does not match root type ${rootType}.`,
        isParsed: false,
      };
    }

    const validationError = getFullCellValidationError(runtime, result.value, cell);
    if (validationError) {
      return {
        title: 'TON Cell',
        ...basePreview,
        fields: [getRawPayloadField(cellBase64)],
        error: validationError,
        isParsed: false,
      };
    }

    const fields: ApiParsedSignDataCellField[] = [];
    appendParsedCellFields(fields, result.value, 'value', 0, varUInteger16FieldsByKind);

    return {
      title: getParsedCellTitle(result.value),
      ...basePreview,
      fields,
      isParsed: true,
    };
  } catch (err) {
    return {
      title: 'TON Cell',
      ...basePreview,
      fields: [getRawPayloadField(cellBase64)],
      error: getErrorMessage(err, 'Failed to parse cell payload.'),
      isParsed: false,
    };
  }
}

function getCellSizeLimitError(cellBase64: string): string | undefined {
  if (cellBase64.length > MAX_CELL_BASE64_LENGTH) {
    return `Cell payload exceeds preview limit (${MAX_CELL_BOC_BYTES} bytes).`;
  }

  const decodedBytes = getBase64DecodedByteLength(cellBase64);
  if (decodedBytes > MAX_CELL_BOC_BYTES) {
    return `Cell payload exceeds preview limit (${MAX_CELL_BOC_BYTES} bytes).`;
  }

  return undefined;
}

function getBase64DecodedByteLength(value: string): number {
  const normalized = value.replace(/\s/g, '');
  if (!normalized) return 0;

  const padding = normalized.endsWith('==') ? 2 : normalized.endsWith('=') ? 1 : 0;
  return Math.max(0, Math.floor((normalized.length * 3) / 4) - padding);
}

function getSchemaLimitError(schema: string): string | undefined {
  if (schema.length > MAX_TLB_SCHEMA_LENGTH) {
    return `TL-B schema exceeds preview limit (${MAX_TLB_SCHEMA_LENGTH} chars).`;
  }

  const { declarationCount, fieldCount } = countTopLevelSchemaItems(schema);
  if (declarationCount > MAX_TLB_DECLARATION_COUNT) {
    return `TL-B schema exceeds preview declaration limit (${MAX_TLB_DECLARATION_COUNT}).`;
  }

  if (fieldCount > MAX_TLB_FIELD_COUNT) {
    return `TL-B schema exceeds preview field limit (${MAX_TLB_FIELD_COUNT}).`;
  }

  return undefined;
}

function countTopLevelSchemaItems(schema: string) {
  let declarationCount = 0;
  let fieldCount = 0;
  let braceDepth = 0;

  for (const char of schema) {
    if (char === '{') {
      braceDepth++;
      continue;
    }

    if (char === '}') {
      braceDepth = Math.max(0, braceDepth - 1);
      continue;
    }

    if (braceDepth > 0) continue;

    if (char === ';') {
      declarationCount++;
    } else if (char === ':') {
      fieldCount++;
    }
  }

  return { declarationCount, fieldCount };
}

function getRootTypeName(runtime: ReturnType<typeof tlbRuntime.parseTLB>): string | undefined {
  const types = getNormalizedRuntimeTypes(runtime);
  return types ? Array.from(types.keys()).at(-1) : undefined;
}

function deserializeRootType(
  runtime: ReturnType<typeof tlbRuntime.parseTLB>,
  rootType: string | undefined,
  slice: Slice,
) {
  if (!rootType) {
    return { success: false as const, error: new Error('TL-B schema does not declare a root type.') };
  }

  const deserializeByTypeName = (runtime as unknown as RuntimeWithNormalizedTypes).deserializeByTypeName;
  if (!deserializeByTypeName) {
    return { success: false as const, error: new Error('TL-B runtime cannot deserialize the declared root type.') };
  }

  return deserializeByTypeName.call(runtime, rootType, slice);
}

/**
 * `tlb-runtime` normalizes constructor field names before returning parsed objects (for example, `var`
 * becomes `var0`). Read its normalized constructor fields rather than source names, so the metadata uses
 * exactly the same field identity as the deserialized values.
 */
function getVarUInteger16FieldsByKind(runtime: ReturnType<typeof tlbRuntime.parseTLB>): VarUInteger16FieldsByKind {
  const types = getNormalizedRuntimeTypes(runtime);
  if (!types) return new Map();

  const fieldsByKind = new Map<string, ReadonlySet<string>>();
  for (const type of types.values()) {
    for (const constructor of type.constructors) {
      const fields = new Set(
        constructor.fields
          .filter(isVarUInteger16RuntimeField)
          .map((field) => field.name),
      );
      fieldsByKind.set(`${type.name}_${constructor.name}`, fields);
    }

    // tlb-runtime uses the result type itself as `kind` when it has one constructor.
    if (type.constructors.length === 1) {
      fieldsByKind.set(type.name, fieldsByKind.get(`${type.name}_${type.constructors[0].name}`)!);
    }
  }

  return fieldsByKind;
}

function getNormalizedRuntimeTypes(
  runtime: ReturnType<typeof tlbRuntime.parseTLB>,
): ReadonlyMap<string, RuntimeType> | undefined {
  const types = (runtime as unknown as RuntimeWithNormalizedTypes).types;
  return types instanceof Map ? types : undefined;
}

function isVarUInteger16RuntimeField(field: RuntimeField): boolean {
  return field.fieldType.kind === 'TLBVarIntegerType'
    && field.fieldType.signed === false
    && getVarUIntegerLimit(field.fieldType.n) === 16;
}

function getVarUIntegerLimit(expression: RuntimeMathExpression | undefined): number | undefined {
  // `tlb-runtime` represents `(VarUInteger n)` as `.(n - 1)`. Read its AST instead of reparsing the source.
  const innerExpression = expression?.operation === '.' ? expression.value : undefined;
  if (innerExpression?.operation !== '-' || innerExpression.right?.n !== 1) return undefined;
  return innerExpression.left?.n;
}

function isRootKind(value: ParsedCell, rootType: string): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value) || isCellLike(value)) return false;
  const kind = (value as Readonly<Record<string, ParsedCell>>).kind;
  return typeof kind === 'string' && (kind === rootType || kind.startsWith(`${rootType}_`));
}

function getFullCellValidationError(
  runtime: ReturnType<typeof tlbRuntime.parseTLB>,
  value: ParsedCell,
  originalCell: Cell,
) {
  try {
    const serialized = runtime.serialize(value);
    if (!serialized.success) {
      return 'TL-B schema could not serialize the parsed preview for full-cell validation.';
    }

    const serializedCell = serialized.value.endCell();
    const serializedHash = Buffer.from(serializedCell.hash()).toString('hex');
    const originalHash = originalCell.hash().toString('hex');

    if (
      serializedHash !== originalHash
      || serializedCell.bits.length !== originalCell.bits.length
      || serializedCell.refs.length !== originalCell.refs.length
    ) {
      return 'TL-B schema did not parse the complete root cell payload.';
    }
  } catch (err) {
    return getErrorMessage(err, 'TL-B schema could not validate the complete root cell payload.');
  }

  return undefined;
}

function appendParsedCellFields(
  fields: ApiParsedSignDataCellField[],
  value: ParsedCell,
  label: string,
  depth: number,
  varUInteger16FieldsByKind: VarUInteger16FieldsByKind,
  varUInteger16FieldNames: ReadonlySet<string> = new Set(),
): void {
  if (fields.length >= MAX_FIELD_COUNT) return;

  if (depth > MAX_FIELD_DEPTH) {
    fields.push({ label, value: '…', depth: MAX_FIELD_DEPTH, isMuted: true });
    return;
  }

  if (Array.isArray(value)) {
    fields.push({ label, value: `Array(${value.length})`, depth, isMuted: true });
    for (const [index, item] of value.entries()) {
      if (fields.length >= MAX_FIELD_COUNT) break;
      appendParsedCellFields(fields, item, `[${index}]`, depth + 1, varUInteger16FieldsByKind);
    }
    return;
  }

  if (isCellLike(value)) {
    const bits = value.bits?.length ?? 0;
    const refs = value.refs?.length ?? 0;
    const hash = toHex(value.hash?.());
    fields.push({
      label,
      value: hash ? `Cell ${shortenHash(hash)} (${bits} bits, ${refs} refs)` : `Cell (${bits} bits, ${refs} refs)`,
      depth,
      isMuted: true,
    });
    return;
  }

  if (isAddressLike(value)) {
    fields.push({ label, value: String(value), depth });
    return;
  }

  if (value && typeof value === 'object') {
    const record = value as Readonly<Record<string, ParsedCell>>;
    const kind = typeof record.kind === 'string' ? record.kind : 'Object';
    const nestedVarUInteger16FieldNames = varUInteger16FieldsByKind.get(kind) ?? new Set<string>();
    fields.push({ label: depth === 0 ? 'kind' : label, value: kind, depth, isMuted: true });

    for (const [key, nestedValue] of Object.entries(record)) {
      if (fields.length >= MAX_FIELD_COUNT) {
        fields.push({ label: '…', value: 'Output truncated', depth: depth + 1, isMuted: true });
        break;
      }

      if (key === 'kind' || nestedValue === undefined) continue;
      appendParsedCellFields(
        fields,
        nestedValue,
        key,
        depth + 1,
        varUInteger16FieldsByKind,
        nestedVarUInteger16FieldNames,
      );
    }
    return;
  }

  fields.push({
    label,
    value: formatParsedScalar(value, varUInteger16FieldNames.has(label)),
    depth,
  });
}

function getParsedCellTitle(value: ParsedCell): string {
  if (value && typeof value === 'object' && !Array.isArray(value) && !isCellLike(value)) {
    const kind = (value as Readonly<Record<string, ParsedCell>>).kind;
    if (typeof kind === 'string' && kind) return kind;
  }

  return 'TON Cell';
}

function formatParsedScalar(value: ParsedCell, isVarUInteger16: boolean): string {
  if (typeof value === 'bigint') {
    // `VarUInteger 16` is an integer encoding, not an asset declaration. `units` deliberately stays neutral.
    if (isVarUInteger16) {
      return `${value.toString()} units`;
    }

    return `${value.toString()} (0x${value.toString(16)})`;
  }

  if (typeof value === 'number') {
    if (Number.isInteger(value) && value > 255) {
      return `${value} (0x${value.toString(16)})`;
    }

    return value.toString();
  }

  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'string') return value;

  return 'null';
}

function getRawPayloadField(cellBase64: string): ApiParsedSignDataCellField {
  return {
    label: 'payload',
    value: `${cellBase64.length} base64 chars`,
    depth: 0,
    isMuted: true,
  };
}

function isCellLike(value: unknown): value is CellLike {
  return Boolean(
    value
    && typeof value === 'object'
    && typeof (value as CellLike).hash === 'function'
    && typeof (value as CellLike).bits?.length === 'number'
    && Array.isArray((value as CellLike).refs),
  );
}

function isAddressLike(value: unknown): boolean {
  if (!value || typeof value !== 'object') return false;
  const constructorName = value.constructor?.name;
  return constructorName === 'Address' || constructorName === 'ExternalAddress';
}

function toHex(value: Buffer | Uint8Array | undefined): string | undefined {
  if (!value) return undefined;
  return Buffer.from(value).toString('hex');
}

export function shortenHash(hash: string): string {
  if (hash.length <= 20) return hash;
  return `${hash.slice(0, 10)}...${hash.slice(-10)}`;
}

function getErrorMessage(err: unknown, fallback: string): string {
  return err instanceof Error && err.message ? err.message : fallback;
}
