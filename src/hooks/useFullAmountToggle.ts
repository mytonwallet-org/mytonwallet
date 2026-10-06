import { formatNumber } from '../util/formatNumber';
import useFlag from './useFlag';
import useLastCallback from './useLastCallback';

/**
 * Splits an amount into its whole and fraction parts, rounded to a short form by default. A click on the amount
 * switches it to the full precision of the token and back.
 */
export default function useFullAmountToggle(value: string, decimals: number) {
  const [isFullAmount, showFullAmount, hideFullAmount] = useFlag();

  const [wholePart, fractionPart] = (isFullAmount
    ? formatNumber(value, decimals, undefined, true)
    : formatNumber(value)
  ).split('.');

  // The mask reveal takes the first tap, so the full amount comes on the second one, and the third one
  // returns the mask (the click is handed back to `SensitiveData` by returning a falsy value)
  const handleAmountClick = useLastCallback(() => {
    if (isFullAmount) {
      hideFullAmount();
      return false;
    }

    showFullAmount();
    return true;
  });

  return { wholePart, fractionPart, handleAmountClick, hideFullAmount };
}
