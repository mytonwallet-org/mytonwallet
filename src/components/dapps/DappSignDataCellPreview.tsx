import React, { memo } from '../../lib/teact/teact';

import type { ApiParsedSignDataCellPreview } from '../../api/dappProtocols/signDataCellPreview';

import useLang from '../../hooks/useLang';

import {
  SignDataFieldRow,
  SignDataLabel,
  SignDataPayloadField,
  SignDataStruct,
  SignDataStructuredBlock,
  signDataStructuredStyles as styles,
} from '../ui/SignDataStructuredView';

interface OwnProps {
  parsedCell: ApiParsedSignDataCellPreview;
}

function DappSignDataCellPreview({ parsedCell }: OwnProps) {
  const lang = useLang();

  return (
    <>
      <SignDataLabel>{lang('Parsed Cell')}</SignDataLabel>
      <SignDataPayloadField isText>
        {parsedCell.title}
      </SignDataPayloadField>

      <SignDataStructuredBlock label={lang('Cell Metadata')} isExpanded>
        <SignDataStruct>
          <SignDataFieldRow name={lang('Bits')}>
            {parsedCell.bits}
          </SignDataFieldRow>
          <SignDataFieldRow name={lang('References')}>
            {parsedCell.refs}
          </SignDataFieldRow>
          {parsedCell.hash && (
            <SignDataFieldRow name={lang('Hash')}>
              {shortenHash(parsedCell.hash)}
            </SignDataFieldRow>
          )}
        </SignDataStruct>
      </SignDataStructuredBlock>

      {parsedCell.error && (
        <SignDataStructuredBlock label={lang('Parsing Error')} className={styles.errorField} isExpanded>
          {parsedCell.error}
        </SignDataStructuredBlock>
      )}

      <SignDataStructuredBlock label={lang('Cell Fields')} isExpanded isText>
        <SignDataStruct>
          {parsedCell.fields.map((field, index) => (
            <SignDataFieldRow
              key={`${field.label}-${index}`}
              name={field.label}
              depth={field.depth}
              isValueMuted={field.isMuted}
            >
              {field.value}
            </SignDataFieldRow>
          ))}
        </SignDataStruct>
      </SignDataStructuredBlock>

    </>
  );
}

export default memo(DappSignDataCellPreview);

function shortenHash(hash: string): string {
  if (hash.length <= 20) return hash;
  return `${hash.slice(0, 10)}...${hash.slice(-10)}`;
}
