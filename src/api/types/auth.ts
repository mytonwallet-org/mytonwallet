import type { getAccountChains } from '../common/accounts';

export interface ApiAuthImportViewAccountResult {
  accountId: string;
  title?: string;
  byChain: ReturnType<typeof getAccountChains>;
  isTemporary?: true;
}
