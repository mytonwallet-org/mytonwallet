// Focus never scrolls the screens the field lies in, which may still be sliding in
export default function focusAtEnd(input: HTMLTextAreaElement) {
  input.focus({ preventScroll: true });
  input.setSelectionRange(input.value.length, input.value.length);
}
