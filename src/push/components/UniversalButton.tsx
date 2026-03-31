import React from '../../lib/teact/teact';

import type { OwnProps as ButtonProps } from '../../components/ui/Button';

import { THEME_DEFAULT } from '../../config';
import { pick } from '../../util/iteratees';
import { isInsideTelegram } from '../../util/telegram';

import useAppTheme from '../../hooks/useAppTheme';
import useTelegramBottomButton from '../hooks/useTelegramBottomButton';

import Button from '../../components/ui/Button';

interface OwnProps extends ButtonProps {
  isActive: boolean;
}

function UniversalButton(props: OwnProps) {
  const appTheme = useAppTheme(THEME_DEFAULT);

  useTelegramBottomButton({
    isActive: props.isActive,
    type: props.isPrimary ? 'main' : 'secondary',
    appTheme,
    ...pick(props, ['isLoading', 'isPrimary', 'isDestructive', 'isDisabled', 'onClick']),
    text: props.children,
  });

  if (isInsideTelegram()) {
    return undefined;
  }

  return (
    <Button {...props} />
  );
}

export default UniversalButton;
