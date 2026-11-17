import type { ApiPriceHistoryPeriod } from '../../../api/types';

const DAY_PERIOD: ApiPriceHistoryPeriod = '1D';

interface Params {
  period: ApiPriceHistoryPeriod;
  isPointSelected: boolean;
  /** The day change reported together with the price, absent where the chart has no such change */
  dayChangePercent?: number;
  /** The first traded price of the period, from `findInitialPoint` */
  initialPrice?: number;
  price?: number;
}

/**
 * The change shown next to the chart price. On the `1D` period without a selected point, `isDayChange` is set
 * and the change is `dayChangePercent`. Otherwise the change runs from `initialPrice` to `price`, and stays
 * empty while either is unknown.
 */
export function resolveChartChange({
  period, isPointSelected, dayChangePercent, initialPrice, price,
}: Params) {
  const isDayChange = period === DAY_PERIOD && !isPointSelected && dayChangePercent !== undefined;
  const changePercent = isDayChange
    ? dayChangePercent
    : initialPrice && price !== undefined ? (price / initialPrice - 1) * 100 : undefined;

  return { isDayChange, changePercent };
}
