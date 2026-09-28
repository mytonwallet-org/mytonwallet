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
  /** Applied to the fee value, including its precision sign, but not to the "Fee" label */
  feeClassName?: string;
  /** Whether the component is rendered on a landscape layout (with a lighter background) */
  isStatic?: boolean;
  isError?: boolean;
  /** If true, the "Details" button will be shown even when no fee can be displayed. */
  keepDetailsButtonWithoutFee?: boolean;
  /** If true, the whole line acts as the details button, and only a chevron is added to the fee */
  noDetailsLabel?: boolean;
  /** If undefined, the details button is not shown */
  onDetailsClick?(): void;
};

function FeeLine({
  className,
  feeClassName,
  isStatic,
  isError,
  terms,
  token,
  precision,
  keepDetailsButtonWithoutFee,
  noDetailsLabel,
  onDetailsClick,
}: OwnProps) {
  const lang = useLang();
  let content: TeactNode | undefined;

  if (terms && token) {
    const langKey = precision === 'exact' ? '$fee_value_with_colon' : '$fee_value';
    const fee = <Fee terms={terms} token={token} precision={precision} />;

    content = lang(langKey, {
      fee: feeClassName ? <span className={feeClassName}>{fee}</span> : fee,
    });
  }

  return (
    <FeeLineContainer
      className={className}
      isStatic={isStatic}
      isError={isError}
      noDetailsLabel={noDetailsLabel}
      onDetailsClick={content || keepDetailsButtonWithoutFee ? onDetailsClick : undefined}
      transitionKey={content ? 1 : 0}
    >
      {content}
    </FeeLineContainer>
  );
}

export default memo(FeeLine);

type ContainerProps = Pick<OwnProps, 'className' | 'isStatic' | 'isError' | 'noDetailsLabel' | 'onDetailsClick'> & {
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
  noDetailsLabel,
  onDetailsClick,
  children,
  transitionKey = 0,
}: ContainerProps) {
  const lang = useLang();

  const fullClassName = buildClassName(
    styles.container, className, isStatic && styles.static, isError && styles.error,
  );
  const activeKey = transitionKey + (onDetailsClick ? 0x10000 : 0);

  function handleDetailsKeyDown(e: React.KeyboardEvent) {
    if (e.key !== 'Enter' && e.key !== ' ') return;

    // Space would otherwise scroll the modal content
    e.preventDefault();
    onDetailsClick!();
  }

  if (noDetailsLabel && onDetailsClick) {
    return (
      <Transition name="fade" activeKey={activeKey} className={fullClassName}>
        <span
          role="button"
          tabIndex={0}
          className={styles.plainDetails}
          onClick={() => onDetailsClick()}
          onKeyDown={handleDetailsKeyDown}
        >
          {children}
          <i
            className={buildClassName('icon-chevron-right', styles.detailsIcon, styles.plainDetailsIcon)}
            aria-hidden
          />
        </span>
      </Transition>
    );
  }

  return (
    <Transition name="fade" activeKey={activeKey} className={fullClassName}>
      {children}
      {Boolean(children) && onDetailsClick && ' · '}
      {onDetailsClick && (
        <span
          role="button"
          tabIndex={0}
          className={styles.details}
          onClick={() => onDetailsClick()}
          onKeyDown={handleDetailsKeyDown}
        >
          {lang('Details')}
          <i className={buildClassName('icon-chevron-right', styles.detailsIcon)} aria-hidden />
        </span>
      )}
    </Transition>
  );
}
