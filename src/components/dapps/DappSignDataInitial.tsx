import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { GlobalState } from '../../global/types';

import { selectCurrentAccount, selectCurrentAccountId, selectHasMultipleAccounts } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { getSignDataWarningKinds } from './signDataWarningPolicy';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';

import AccountSwitcherPill from '../common/AccountSwitcherPill';
import Button from '../ui/Button';
import Eip712TypedDataView from '../ui/Eip712TypedDataView';
import ModalHeader from '../ui/ModalHeader';
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
> & {
  currentAccountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
};

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
  currentAccountId,
  accountTitle,
  hasMultipleAccounts,
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

  useEffect(() => (
    isActive && canSubmit
      ? captureKeyboardListeners({ onEnter: () => submitDappSignDataConfirm() })
      : undefined
  ), [isActive, canSubmit, submitDappSignDataConfirm]);

  function renderContent() {
    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <DappInfoWithAccount dapp={dapp} />

        {renderSignDataByType()}
        {renderSignDataWarnings()}

        <div className={buildClassName(modalStyles.buttons, styles.transferButtons)}>
          <Button className={modalStyles.button} onClick={closeDappSignData}>{lang('Cancel')}</Button>
          <Button
            isPrimary
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
      <div className={styles.headerWithPill}>
        <ModalHeader title={lang('Sign Data')} onClose={closeDappSignData} />
        {hasMultipleAccounts && currentAccountId && (
          <AccountSwitcherPill
            accountId={currentAccountId}
            title={accountTitle}
            className={styles.accountPill}
          />
        )}
      </div>
      {isDappLoading
        ? <DappSkeletonWithContent rows={skeletonRows} />
        : renderContent()}
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
    currentAccountId: selectCurrentAccountId(global),
    accountTitle: selectCurrentAccount(global)?.title,
    hasMultipleAccounts: selectHasMultipleAccounts(global),
  };
})(DappSignDataInitial));
