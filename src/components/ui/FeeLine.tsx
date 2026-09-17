import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { OwnProps as FeeProps } from './Fee';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import Fee from './Fee';
import Transition from './Transition';

import styles from './FeeLine.module.scss';

/**
 * The component will be rendered empty unless all the required options from `FeeProps` are provided.
 * After that it will fade in.
 */
type OwnProps = Partial<Pick<FeeProps, 'terms' | 'token'>> & Pick<FeeProps, 'precision'> & {
  className?: string;
  /** Whether the component is rendered on a landscape layout (with a lighter background) */
  isStatic?: boolean;
  isError?: boolean;
  /** If true, the "Details" button will be shown even when no fee can be displayed. */
  keepDetailsButtonWithoutFee?: boolean;
  /** If undefined, the details button is not shown */
  onDetailsClick?(): void;
};

function FeeLine({
  className,
  isStatic,
  isError,
  terms,
  token,
  precision,
  keepDetailsButtonWithoutFee,
  onDetailsClick,
}: OwnProps) {
  const lang = useLang();
  let content: TeactNode | undefined;

  if (terms && token) {
    const langKey = precision === 'exact' ? '$fee_value_with_colon' : '$fee_value';
    content = lang(langKey, {
      fee: <Fee terms={terms} token={token} precision={precision} />,
    });
  }

  return (
    <FeeLineContainer
      className={className}
      isStatic={isStatic}
      isError={isError}
      onDetailsClick={content || keepDetailsButtonWithoutFee ? onDetailsClick : undefined}
      transitionKey={content ? 1 : 0}
    >
      {content}
    </FeeLineContainer>
  );
}

export default memo(FeeLine);

type ContainerProps = Pick<OwnProps, 'className' | 'isStatic' | 'isError' | 'onDetailsClick'> & {
  children?: TeactNode;
  transitionKey?: number;
};

/**
 * Use this component when you want to show a content that looks like `FeeLine`, but is not `FeeLine`.
 */
export function FeeLineContainer({
  className,
  isStatic,
  isError,
  onDetailsClick,
  children,
  transitionKey = 0,
}: ContainerProps) {
  const lang = useLang();

  return (
    <Transition
      name="fade"
      activeKey={transitionKey + (onDetailsClick ? 0x10000 : 0)}
      className={buildClassName(styles.container, className, isStatic && styles.static, isError && styles.error)}
    >
      {children}
      {Boolean(children) && onDetailsClick && ' · '}
      {onDetailsClick && (
        <span
          role="button"
          tabIndex={0}
          className={styles.details}
          onClick={() => onDetailsClick()}
        >
          {lang('Details')}
          <i className={buildClassName('icon-chevron-right', styles.detailsIcon)} aria-hidden />
        </span>
      )}
    </Transition>
  );
}
