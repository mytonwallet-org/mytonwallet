import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { GlobalState } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { pick } from '../../util/iteratees';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';

import Button from '../ui/Button';
import Eip712TypedDataView from '../ui/Eip712TypedDataView';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';
import DappInfoWithAccount from './DappInfoWithAccount';
import DappSkeletonWithContent, { type DappSkeletonRow } from './DappSkeletonWithContent';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

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
            <div className={styles.warning}>
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

            <div className={styles.warning}>
              {lang('The binary data content is unclear. Sign it only if you trust the service.')}
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
