import { IS_GRAM_WALLET } from '../config';

export function buildMfaStartParam(id: string) {
  return `${IS_GRAM_WALLET ? 'g' : 'm'}_${id}`;
}
