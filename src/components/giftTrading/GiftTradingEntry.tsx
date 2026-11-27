import React, { useLayoutEffect, useRef, useState } from '../../lib/teact/teact';
import useHistoryBack from '../../hooks/useHistoryBack';

import Button from '../ui/Button';
import Portal from '../ui/Portal';
import GiftTradingLab from './GiftTradingLab';

function GiftTradingDialog({ onClose }: { onClose: () => void }) {
  const dialogRef = useRef<HTMLDialogElement>();
  useLayoutEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return undefined;
    const launcher = document.activeElement;
    const handleCancel = (event: Event) => {
      event.preventDefault();
      onClose();
    };
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || !dialog.open) return;
      event.stopImmediatePropagation();
      handleCancel(event);
    };
    const wrapTab = (event: KeyboardEvent) => {
      if (event.key !== 'Tab' || !dialog.open) return;
      const controls = Array.from(dialog.querySelectorAll<HTMLElement>(
        'button, input, select, textarea, a[href], [tabindex]',
      )).filter(control => control.tabIndex >= 0 && !control.matches(':disabled')
        && !control.closest('[inert]') && control.getClientRects().length > 0
        && getComputedStyle(control).visibility === 'visible');
      const first = controls[0];
      const last = controls.at(-1);
      if (!first || !last) return;
      const active = document.activeElement;
      if (active !== dialog && active !== (event.shiftKey ? first : last)) return;
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
    };
    dialog.addEventListener('cancel', handleCancel);
    dialog.addEventListener('keydown', wrapTab);
    window.addEventListener('keydown', handleEscape, true);
    dialog.showModal();
    return () => {
      dialog.removeEventListener('cancel', handleCancel);
      dialog.removeEventListener('keydown', wrapTab);
      window.removeEventListener('keydown', handleEscape, true);
      dialog.close();
      if (launcher instanceof HTMLElement && launcher.isConnected) launcher.focus();
    };
  }, []);

  return (
    <dialog
      ref={dialogRef}
      className="gift-trading-dialog"
      aria-label="Gift trading local test"
    >
      <GiftTradingLab onClose={onClose} />
    </dialog>
  );
}

export default function GiftTradingEntry() {
  const [isOpen, setIsOpen] = useState(false);
  function close() {
    setIsOpen(false);
  }
  useHistoryBack({ isActive: isOpen, onBack: close });

  return (
    <>
      <Button onClick={() => setIsOpen(true)}>Open synthetic gift trading</Button>
      {isOpen && <Portal><GiftTradingDialog onClose={close} /></Portal>}
    </>
  );
}
