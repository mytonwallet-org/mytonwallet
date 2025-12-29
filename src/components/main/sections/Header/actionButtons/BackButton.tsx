import React, { memo } from '../../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../../global';

import type { OwnProps as ButtonProps } from '../../../../ui/Button';

import buildClassName from '../../../../../util/buildClassName';

import useLang from '../../../../../hooks/useLang';
import useLastCallback from '../../../../../hooks/useLastCallback';

import Button from '../../../../ui/Button';

import styles from './BackButton.module.scss';
import buttonStyles from './Buttons.module.scss';

interface OwnProps {
  isIconOnly?: boolean;
}

interface StateProps {
  accountId?: string;
}

function BackButton({ isIconOnly, accountId }: OwnProps & StateProps) {
  const { signOut } = getActions();

  const lang = useLang();

  const handleSignOutClick = useLastCallback(() => {
    signOut({
      level: 'account',
      accountId,
    });
  });

  const props: Partial<ButtonProps> = {
    isText: true,
    isSimple: true,
    kind: isIconOnly ? 'transparent' : undefined,
    ariaLabel: isIconOnly ? lang('Back') : undefined,
    className: isIconOnly ? buttonStyles.button : styles.backButton,
    onClick: accountId ? handleSignOutClick : undefined,
  };

  return (
    <Button {...props}>
      <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />
      {isIconOnly ? undefined : lang('Back')}
    </Button>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    accountId: global.currentTemporaryViewAccountId,
  };
})(BackButton));
