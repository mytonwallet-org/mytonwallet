import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './SignDataStructuredView.module.scss';

interface SignDataLabelProps {
  children: TeactNode;
}

interface SignDataPayloadFieldProps {
  children: TeactNode;
  className?: string;
  isExpanded?: boolean;
  isText?: boolean;
}

interface SignDataStructuredBlockProps extends SignDataPayloadFieldProps {
  label: TeactNode;
}

interface SignDataStructProps {
  children: TeactNode;
  depth?: number;
}

interface SignDataFieldRowProps {
  name: TeactNode;
  children: TeactNode;
  depth?: number;
  isValueMuted?: boolean;
}

export function SignDataLabel({ children }: SignDataLabelProps) {
  return <p className={styles.label}>{children}</p>;
}

export function SignDataPayloadField({
  children, className, isExpanded, isText,
}: SignDataPayloadFieldProps) {
  return (
    <div
      className={buildClassName(
        styles.payloadField,
        isExpanded && styles.payloadField_expanded,
        isText && styles.payloadField_text,
        className,
      )}
    >
      {children}
    </div>
  );
}

export function SignDataStructuredBlock({
  label, children, className, isExpanded, isText,
}: SignDataStructuredBlockProps) {
  return (
    <div className={styles.typedBlock}>
      <SignDataLabel>{label}</SignDataLabel>
      <SignDataPayloadField className={className} isExpanded={isExpanded} isText={isText}>
        {children}
      </SignDataPayloadField>
    </div>
  );
}

export function SignDataStruct({ children, depth = 0 }: SignDataStructProps) {
  return (
    <div className={styles.struct} style={depth ? `margin-left: ${depth}rem` : undefined}>
      {children}
    </div>
  );
}

export function SignDataFieldRow({
  name, children, depth = 0, isValueMuted,
}: SignDataFieldRowProps) {
  return (
    <div className={styles.fieldRow} style={depth ? `margin-left: ${depth}rem` : undefined}>
      <div className={styles.fieldName}>{name}</div>
      <div className={buildClassName(styles.fieldValue, isValueMuted && styles.fieldValue_muted)}>
        {children}
      </div>
    </div>
  );
}

export { styles as signDataStructuredStyles };

export default memo(SignDataStructuredBlock);
