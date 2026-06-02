export interface ApiTransaction {
  payload: string;
  signature: string;
  address: string;
}

export interface ApiInstallRequest {
  address: string;
  telegramId?: string;
}
