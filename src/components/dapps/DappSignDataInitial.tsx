import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { EvmEip712SignDataPayload } from '../../api/dappProtocols/adapters/walletConnect/types';
import type { GlobalState } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { pick } from '../../util/iteratees';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';

import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';
import DappInfoWithAccount from './DappInfoWithAccount';
import DappSkeletonWithContent, { type DappSkeletonRow } from './DappSkeletonWithContent';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

const MAX_EIP712_DEPTH = 32;

type Eip712TypeDefinitions = EvmEip712SignDataPayload['types'];

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
      <div className={styles.eip712Struct}>
        {Object.keys(value as Record<string, unknown>).sort().map((key) => (
          <div key={key} className={styles.eip712FieldRow}>
            <div className={styles.eip712FieldName}>{key}</div>
            <div className={styles.eip712FieldValue}>
              {renderEip712LeafUnknown((value as Record<string, unknown>)[key])}
            </div>
          </div>
        ))}
      </div>
    );
  }
  if (Array.isArray(value)) {
    return (
      <div className={styles.eip712Array}>
        {value.map((item, index) => (
          <div key={index} className={styles.eip712ArrayItem}>
            <span className={styles.eip712ArrayIndex}>{`[${index}]`}</span>
            <div className={styles.eip712FieldValue}>{renderEip712LeafUnknown(item)}</div>
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
      <div className={styles.eip712Array}>
        {items.map((item, index) => (
          <div key={`${keyPrefix}-${index}`} className={styles.eip712ArrayItem}>
            <span className={styles.eip712ArrayIndex}>{`[${index}]`}</span>
            <div className={styles.eip712FieldValue}>
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
    <div className={styles.eip712Struct} style={`margin-left: ${depth}rem`}>
      {fields.map((field) => (
        <div
          key={`${keyPrefix}-${field.name}`}
          className={styles.eip712FieldRow}
        >
          <div className={styles.eip712FieldName}>{field.name}</div>
          <div className={styles.eip712FieldValue}>
            {renderEip712Value(obj[field.name], field.type, types, depth + 1, `${keyPrefix}-${field.name}`)}
          </div>
        </div>
      ))}
    </div>
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

type StateProps = Pick<GlobalState['currentDappSignData'], 'dapp' | 'isLoading' | 'payloadToSign'>;

const skeletonRows: DappSkeletonRow[] = [
  { isLarge: false, hasFee: false },
];

function DappSignDataInitial({
  dapp,
  isLoading,
  payloadToSign,
}: StateProps) {
  const { closeDappSignData, submitDappSignDataConfirm } = getActions();

  const lang = useLang();
  const renderingPayloadToSign = useCurrentOrPrev(payloadToSign, true);

  const isDappLoading = dapp === undefined;

  function renderContent() {
    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <DappInfoWithAccount dapp={dapp} />

        {renderSignDataByType()}

        <div className={buildClassName(modalStyles.buttons, styles.transferButtons)}>
          <Button className={modalStyles.button} onClick={closeDappSignData}>{lang('Cancel')}</Button>
          <Button
            isPrimary
            isSubmit
            isLoading={isLoading}
            className={modalStyles.button}
            onClick={submitDappSignDataConfirm}
          >
            {lang('Sign')}
          </Button>
        </div>
      </div>
    );
  }

  function renderSignDataByType() {
    switch (renderingPayloadToSign?.type) {
      case 'text': {
        const { text } = renderingPayloadToSign;

        return (
          <>
            <p className={styles.label}>{lang('Message')}</p>
            <div className={buildClassName(styles.payloadField, styles.payloadField_text)}>
              {text}
            </div>
          </>
        );
      }

      case 'binary': {
        const { bytes } = renderingPayloadToSign;

        return (
          <>
            <p className={styles.label}>{lang('Binary Data')}</p>
            <div className={buildClassName(styles.payloadField, styles.payloadField_expanded)}>
              {bytes}
            </div>
            <div className={styles.warningForPayload}>
              {lang('The binary data content is unclear. Sign it only if you trust the service.')}
            </div>
          </>
        );
      }

      case 'cell': {
        const { cell, schema } = renderingPayloadToSign;

        return (
          <>
            {!!schema && (
              <>
                <p className={styles.label}>{lang('Cell Schema')}</p>
                <div className={buildClassName(styles.payloadField, styles.payloadField_text)}>
                  {schema}
                </div>
              </>
            )}

            <p className={styles.label}>{lang('Cell Data')}</p>
            <div className={buildClassName(styles.dataField, styles.payloadField, styles.payloadField_expanded)}>
              {cell}
            </div>

            <div className={styles.warningForPayload}>
              {lang('The binary data content is unclear. Sign it only if you trust the service.')}
            </div>
          </>
        );
      }

      case 'eip712': {
        const { domain, types, primaryType, message } = renderingPayloadToSign;

        return (
          <>
            <p className={styles.label}>{lang('EIP-712 typed data')}</p>
            <p className={styles.label}>{lang('Primary type')}</p>
            <div className={buildClassName(styles.payloadField, styles.payloadField_text)}>
              {primaryType}
            </div>

            <div className={styles.eip712TypedBlock}>
              <p className={styles.label}>{lang('EIP-712 domain')}</p>
              <div
                className={buildClassName(
                  styles.payloadField,
                  styles.payloadField_expanded,
                  styles.payloadField_text,
                )}
              >
                {renderEip712DomainBlock(domain, types)}
              </div>
            </div>

            <div className={styles.eip712TypedBlock}>
              <p className={styles.label}>{lang('Message')}</p>
              <div
                className={buildClassName(
                  styles.payloadField,
                  styles.payloadField_expanded,
                  styles.payloadField_text,
                )}
              >
                {renderEip712MessageBlock(message, primaryType, types)}
              </div>
            </div>
          </>
        );
      }
    }
  }

  return (
    <Transition
      name="semiFade"
      activeKey={isDappLoading ? 0 : 1}
      slideClassName={styles.skeletonTransitionWrapper}
    >
      <ModalHeader title={lang('Sign Data')} onClose={closeDappSignData} />
      {isDappLoading
        ? <DappSkeletonWithContent rows={skeletonRows} />
        : renderContent()}
    </Transition>
  );
}

export default memo(withGlobal((global): StateProps => pick(
  global.currentDappSignData,
  ['dapp', 'isLoading', 'payloadToSign'],
))(DappSignDataInitial));
