import type { AgentAnswerTableReferenceV1, AgentAnswerTableV1 } from '../types';

import {
  AgentV2ContractError, array, boundedInteger, boundedString, fail, literal, object,
} from '../wireReader';

const TABLE_ID_PATTERN = /^t[1-9][0-9]*$/;

export function decodeAnswerTable(value: unknown, path: string): AgentAnswerTableV1 {
  const table = object(value, path);
  const id = decodeTableId(table.id, `${path}.id`);
  const content = object(table.content, `${path}.content`);
  literal(content.kind, 'display', `${path}.content.kind`);
  const headers = array(content.headers, `${path}.headers`, 12)
    .map((header) => boundedString(header, `${path}.header`, 1, 80));
  if (!headers.length) fail(`${path}.headers`);
  const rows = array(content.rows, `${path}.rows`, 320).map((row) => {
    const cells = array(row, `${path}.row`, 12).map((cell) => boundedString(cell, `${path}.cell`, 0, 512));
    if (cells.length !== headers.length) fail(`${path}.row`);
    return cells;
  });
  const notes = array(content.notes, `${path}.notes`, 16)
    .map((note) => boundedString(note, `${path}.note`, 1, 160));
  return { id, content: { kind: 'display', headers, rows, notes } };
}

export function decodeAnswerTableReference(value: unknown, path: string): AgentAnswerTableReferenceV1 {
  const reference = object(value, path);
  return { tableId: decodeTableId(reference.tableId, `${path}.tableId`),
    textOffset: boundedInteger(reference.textOffset, `${path}.textOffset`, 0, 200_000) };
}

export function decodeMessageTables(
  content: Record<string, unknown>, path: string, onInvalid?: (error: AgentV2ContractError) => void,
) {
  if (content.tables === undefined && content.tableReferences === undefined) return;
  const tables: AgentAnswerTableV1[] = [];
  const references: AgentAnswerTableReferenceV1[] = [];
  for (const [index, value] of array(content.tables, `${path}.tables`, 16).entries()) {
    try {
      const table = decodeAnswerTable(value, `${path}.tables[${index}]`);
      if (tables.some(({ id }) => id === table.id)) fail(`${path}.tables[${index}].id`);
      tables.push(table);
    } catch (error) {
      if (!(error instanceof AgentV2ContractError)) throw error;
      onInvalid?.(error);
    }
  }
  for (const [index, value] of array(content.tableReferences, `${path}.tableReferences`, 16).entries()) {
    try {
      const reference = decodeAnswerTableReference(value, `${path}.tableReferences[${index}]`);
      if (!tables.some(({ id }) => id === reference.tableId)
        || references.some(({ tableId }) => tableId === reference.tableId)
        || reference.textOffset < (references[references.length - 1]?.textOffset ?? 0)
        || reference.textOffset > String(content.text).length) fail(`${path}.tableReferences[${index}]`);
      references.push(reference);
    } catch (error) {
      if (!(error instanceof AgentV2ContractError)) throw error;
      onInvalid?.(error);
    }
  }
  content.tables = tables;
  content.tableReferences = references;
}

function decodeTableId(value: unknown, path: string) {
  const id = boundedString(value, path, 1, 16);
  if (!TABLE_ID_PATTERN.test(id)) fail(path);
  return id;
}
