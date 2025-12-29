import type { TraceOutput } from '../chains/ton/types';
import type { ApiActivity } from './activities';

export type ApiEmulationResult = {
  networkFee: bigint;
  /** How much native token will return back as a result of the transactions */
  received: bigint;
  /** Sometimes the array contains fewer indices than the number of transactions */
  traceOutputs: TraceOutput[];
  /** What else should happen after submitting the transactions (in addition to the transactions and the returned native token) */
  activities: ApiActivity[];
  /** The total real fee of `activities` (makes no sense without them) */
  realFee: bigint;
};
