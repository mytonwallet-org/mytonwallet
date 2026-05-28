export type ApiPortfolioHistoryList = Array<[number, number | null]>;

export type ApiPortfolioHistoryParams = {
  // `from`/`to` accept ISO strings or unix-second numbers
  from?: number | string;
  to?: number | string;
  density?: string;
};

export type ApiPortfolioHistoryDataset = {
  assetId: number;
  symbol: string;
  contractAddress: string;
  color?: string;
  impact?: number;
  points: ApiPortfolioHistoryList;
};

export type ApiPortfolioHistoryResponse = {
  status: string;
  points?: ApiPortfolioHistoryList;
  datasets?: ApiPortfolioHistoryDataset[];
  base: string;
  density: string;
  historyScanCursor?: number;
  isAssetLimitExceeded?: boolean;
};
