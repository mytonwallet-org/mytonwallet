import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { GlobalState } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { getSignDataWarningKinds } from './signDataWarningPolicy';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Eip712TypedDataView from '../ui/Eip712TypedDataView';
import ModalFooter from '../ui/ModalFooter';
import Transition from '../ui/Transition';
import DappInfoWithAccount from './DappInfoWithAccount';
import DappSignDataCellPreview from './DappSignDataCellPreview';
import DappSkeletonWithContent, { type DappSkeletonRow } from './DappSkeletonWithContent';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

interface OwnProps {
  isActive?: boolean;
}

type StateProps = Pick<
  GlobalState['currentDappSignData'],
  'dapp' | 'isLoading' | 'payloadToSign' | 'parsedPayloadToSign'
>;

type RenderingSignData = Pick<StateProps, 'payloadToSign' | 'parsedPayloadToSign'>;

const skeletonRows: DappSkeletonRow[] = [
  { isLarge: false, hasFee: false },
];

function DappSignDataInitial({
  isActive,
  dapp,
  isLoading,
  payloadToSign,
  parsedPayloadToSign,
}: OwnProps & StateProps) {
  const { closeDappSignData, submitDappSignDataConfirm } = getActions();

  const lang = useLang();
  const renderingSignData = useCurrentOrPrev<RenderingSignData | undefined>(
    payloadToSign ? { payloadToSign, parsedPayloadToSign } : undefined,
    true,
  );
  const renderingPayloadToSign = renderingSignData?.payloadToSign;
  const renderingParsedPayloadToSign = renderingSignData?.parsedPayloadToSign;

  const isDappLoading = dapp === undefined;
  const canSubmit = !isDappLoading && !isLoading;

  const handleEnter = useLastCallback((e: KeyboardEvent) => {
    // Enter on a focused control, such as Cancel, activates that control instead of signing
    if ((e.target as HTMLElement).closest('button, [role="button"]')) return;

    submitDappSignDataConfirm();
  });

  useEffect(() => (
    isActive && canSubmit
      ? captureKeyboardListeners({ onEnter: { handler: handleEnter, noStopPropagation: true } })
      : undefined
  ), [isActive, canSubmit, handleEnter]);

  function renderContent() {
    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <DappInfoWithAccount dapp={dapp} />

        {renderSignDataByType()}
        {renderSignDataWarnings()}
        {renderFooter()}
      </div>
    );
  }

  // The loading state has no modal header either, so Cancel is the only way to leave a request that never arrives
  function renderSkeleton() {
    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <DappSkeletonWithContent rows={skeletonRows} />
        {renderFooter()}
      </div>
    );
  }

  function renderFooter() {
    return (
      <ModalFooter>
        <div className={buildClassName(modalStyles.buttons, modalStyles.buttonsNoExtraSpace)}>
          <Button className={modalStyles.button} onClick={closeDappSignData}>{lang('Cancel')}</Button>
          <Button
            isPrimary
            isLoading={isLoading}
            isDisabled={isDappLoading}
            className={modalStyles.button}
            onClick={canSubmit ? submitDappSignDataConfirm : undefined}
          >
            {lang('Sign')}
          </Button>
        </div>
      </ModalFooter>
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

            {renderingParsedPayloadToSign && (
              <DappSignDataCellPreview parsedCell={renderingParsedPayloadToSign} />
            )}

            <p className={styles.label}>{lang('Cell Data')}</p>
            <div className={buildClassName(styles.dataField, styles.payloadField, styles.payloadField_expanded)}>
              {cell}
            </div>
          </>
        );
      }

      case 'eip712': {
        const { domain, types, primaryType, message } = renderingPayloadToSign;

        return (
          <Eip712TypedDataView
            domain={domain}
            types={types}
            primaryType={primaryType}
            message={message}
          />
        );
      }
    }
  }

  function renderSignDataWarnings() {
    const warnings = getSignDataWarningKinds(renderingPayloadToSign);
    if (!warnings.length) return undefined;

    return (
      <div className={styles.signDataWarnings}>
        {warnings.map((warning) => (
          <div key={warning} className={styles.warning}>
            {lang('$signature_warning')}
          </div>
        ))}
      </div>
    );
  }

  return (
    <Transition
      name="semiFade"
      activeKey={isDappLoading ? 0 : 1}
      slideClassName={styles.skeletonTransitionWrapper}
    >
      {isDappLoading ? renderSkeleton() : renderContent()}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { dapp, isLoading, payloadToSign, parsedPayloadToSign } = global.currentDappSignData;

  return {
    dapp,
    isLoading,
    payloadToSign,
    parsedPayloadToSign,
  };
})(DappSignDataInitial));
