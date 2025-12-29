import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ToastType } from '../../global/types';

import { pick } from '../../util/iteratees';

import Toast from '../ui/Toast';

type StateProps = {
  toasts: ToastType[];
};

function Toasts({ toasts }: StateProps) {
  const { dismissToast } = getActions();

  if (!toasts.length) {
    return undefined;
  }

  return (
    <div>
      {toasts.map(({ message, icon }) => (
        <Toast
          key={message}
          icon={icon}
          message={message}

          onDismiss={dismissToast}
        />
      ))}
    </div>
  );
}

export default memo(withGlobal(
  (global): StateProps => pick(global, ['toasts']),
)(Toasts));
