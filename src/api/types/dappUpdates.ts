export type ApiSiteUpdateDeeplinkHook = {
  type: 'updateDeeplinkHook';
  isEnabled: boolean;
};

export type ApiSiteDisconnect = {
  type: 'disconnectSite';
  url: string;
};

export type ApiSiteUpdate =
  | ApiSiteUpdateDeeplinkHook
  | ApiSiteDisconnect;

export type OnApiSiteUpdate = (update: ApiSiteUpdate) => void;
