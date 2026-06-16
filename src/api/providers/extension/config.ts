import { IS_CORE_WALLET } from '../../../config';

export const POPUP_PORT = IS_CORE_WALLET ? 'TonWallet_popup' : 'MyWallet_popup';
export const CONTENT_SCRIPT_PORT = IS_CORE_WALLET ? 'TonWallet_contentScript' : 'MyWallet_contentScript';
export const PAGE_CONNECTOR_CHANNEL = IS_CORE_WALLET ? 'TonWallet_pageConnector' : 'MyWallet_pageConnector';
