import { getIsInBackground } from '../util/backgroundMode';
import useDerivedState from './useDerivedState';

export default function useIsInForeground() {
  return !useDerivedState(getIsInBackground);
}
