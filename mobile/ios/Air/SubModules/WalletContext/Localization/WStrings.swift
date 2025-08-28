//
//  WStrings.swift
//  WalletContext
//
//  Created by Sina on 3/16/24.
//

import Foundation

public enum WStrings: String {
    case Language_Active = "Language.Active"
    
    case Alert_OK = "Alert.OK"
    case Alert_NetworkErrorTitle = "Alert.NetworkErrorTitle";
    case Alert_NetworkErrorText = "Alert.NetworkErrorText";
    
    case Common_Remove = "Common.Remove"
    case Common_Warning = "Common.Warning"
    case Intro_Title = "Intro.Title"
    case Intro_Text = "Intro.Text"
    case Intro_CreateWallet = "Intro.CreateWallet"
    case Intro_ImportExisting = "Intro.ImportExisting"
    case Intro_CreateErrorTitle = "Intro.CreateErrorTitle"
    case Intro_CreateErrorText = "Intro.CreateErrorText"
    
    case Created_Title = "Created.Title"
    case Created_Text = "Created.Text"
    case Created_Proceed = "Created.Proceed"
    case Created_Cancel = "Created.Cancel"

    case Words_Title = "Words.Title"
    case Words_Text = "Words.Text"
    case Words_Done = "Words.Done"
    case Words_NotDoneTitle = "Words.NotDoneTitle"
    case Words_NotDoneText = "Words.NotDoneText"
    case Words_NotDoneOk = "Words.NotDoneOk"
    case Words_NotDoneResponse = "Words.NotDoneResponse"
    case Words_NotDoneSkip = "Words.NotDoneSkip"

    case WordCheck_Title = "WordCheck.Title"
    case WordCheck_Text = "WordCheck.Text"
    case WordCheck_Continue = "WordCheck.Continue"
    case WordCheck_IncorrectHeader = "WordCheck.IncorrectHeader"
    case WordCheck_IncorrectText = "WordCheck.IncorrectText"
    case WordCheck_TryAgain = "WordCheck.TryAgain"
    case WordCheck_ViewWords = "WordCheck.ViewWords"

    case WordImport_Title = "WordImport.Title";
    case WordImport_Text = "WordImport.Text";
    case WordImport_Continue = "WordImport.Continue"
    case WordImport_PasteFromClipboard = "WordImport.PasteFromClipboard";
    case WordImport_IncorrectTitle = "WordImport.IncorrectTitle"
    case WordImport_IncorrectText = "WordImport.IncorrectText"
    case WordImport_UnknownErrorTitle = "WordImport.UnknownErrorTitle";
    case WordImport_UnknownErrorText = "WordImport.UnknownErrorText";
    case WordImport_Importing = "WordImport.Importing"

    case ImportSuccessful_Title = "ImportSuccessful.Title"

    case SetPasscode_Title = "SetPasscode.Title"
    case SetPasscode_Text = "SetPasscode.Text"
    case SetPasscode_FourDigitCode = "SetPasscode.FourDigitCode"
    case SetPasscode_SixDigitCode = "SetPasscode.SixDigitCode"
    case SetPasscode_PasscodesDoNotMatch = "SetPasscode.PasscodesDoNotMatch"
    case ConfirmPasscode_Title = "ConfirmPasscode.Title"
    case ConfirmPasscode_Text = "ConfirmPasscode.Text"

    case ChangePasscode_Title = "ChangePasscode.Title"
    case ChangePasscode_NewPassTitle = "ChangePasscode.NewPassTitle"
    case ChangePasscode_NewPassVerifyTitle = "ChangePasscode.NewPassVerifyTitle"

    case Biometric_Reason = "Biometric.Reason"
    case Biometric_NotAvailableTitle = "Biometric.NotAvailableTitle"
    case Biometric_NotAvailableText = "Biometric.NotAvailableText"

    case Biometric_FaceID_Title = "Biometric.FaceID.Title"
    case Biometric_FaceID_Text = "Biometric.FaceID.Text"
    case Biometric_FaceID_Enable = "Biometric.FaceID.Enable"
    case Biometric_FaceID_Skip = "Biometric.FaceID.Skip"

    case Biometric_TouchID_Title = "Biometric.TouchID.Title"
    case Biometric_TouchID_Text = "Biometric.TouchID.Text"
    case Biometric_TouchID_Enable = "Biometric.TouchID.Enable"
    case Biometric_TouchID_Skip = "Biometric.TouchID.Skip"
    
    case Completed_Title = "Completed.Title"
    case Completed_Text = "Completed.Text"
    case Completed_ViewWallet = "Completed.ViewWallet"

    case RestoreFailed_Title = "RestoreFailed.Title"
    case RestoreFailed_Text = "RestoreFailed.Text"
    case RestoreFailed_EnterWords = "RestoreFailed.EnterWords"
    case RestoreFailed_CreateWallet = "RestoreFailed.CreateWallet"

    case Navigation_Cancel = "Navigation.Cancel"
    case Navigation_Done = "Navigation.Done"
    case Navigation_Back = "Navigation.Back"
    case Navigation_Close = "Navigation.Close"

    case Unlock_Wallet = "Unlock.Wallet"
    case Unlock_Title = "Unlock.Title"
    case Unlock_Hint = "Unlock.Hint"
    case Unlock_HintWithTouchID = "Unlock.HintWithTouchID"
    case Unlock_HintWithFaceID = "Unlock.HintWithFaceID"

    case Tabs_Home = "Tabs.Home"
    case Tabs_Assets = "Tabs.Assets"
    case Tabs_Browser = "Tabs.Browser"
    case Tabs_Settings = "Tabs.Settings"
    
    case Home_WaitingForNetwork = "Home.WaitingForNetwork"
    case Home_Updating = "Home.Updating"
    case Home_MainWallet = "Home.MainWallet"
    case Home_Add = "Home.Add"
    case Home_Send = "Home.Send"
    case Home_Earn = "Home.Earn"
    case Home_Earn_Unstaking = "Home.Earn.Unstaking"
    case Home_Earn_Earning = "Home.Earn.Earning"
    case Home_Swap = "Home.Swap"
    case Home_WalletCreated = "Home.WalletCreated"
    case Home_NoActivityTitle = "Home.NoActivityTitle"
    case Home_NoActivitySubtitle = "Home.NoActivitySubtitle"
    case Home_Sending = "Home.Sending"
    case Home_Sent = "Home.Sent"
    case Home_Received = "Home.Received"
    case Home_Swap_Completed = "Home.Swap.Completed"
    case Home_Swap_Pending = "Home.Swap.Pending"
    case Home_Swap_InProgress = "Home.Swap.InProgress"
    case Home_Swap_Failed = "Home.Swap.Failed"
    case Home_Swap_Expired = "Home.Swap.Expired"
    case Home_SentNFT = "Home.SentNFT"
    case Home_ReceivedNFT = "Home.ReceivedNFT"
    case Home_NFT = "Home.NFT"
    case Home_StandaloneNFT = "Home.StandaloneNFT"
    case Home_Staked = "Home.Staked"
    case Home_Unstaked = "Home.Unstaked"
    case Home_UnstakeRequest = "Home.UnstakeRequest"
    case Home_MultiChain = "Home.MultiChain"
    case Home_YourAddresses = "Home.YourAddresses"

    case Home_BuyWithCard = "Home.BuyWithCard"
    case Home_BuyWithCrypto = "Home.BuyWithCrypto"
    case Home_ReceiveQR = "Home.ReceiveQR"
    case Home_Cancel = "Home.Cancel"
    case Home_EnterWalletName = "Home.EnterWalletName"
    case Home_SeeAllTokens = "Home.SeeAllTokens"
    case Home_SeeAllCollectibles = "Home.SeeAllCollectibles"
    case Home_NoCollectibles = "Home.NoCollectibles"
    case Home_ExploreMarketplace = "Home.ExploreMarketplace"

    case ReceiveChain_ChooseNetwork = "ReceiveChain.ChooseNetwork"
    case ReceiveChain_Back = "ReceiveChain.Back"

    case Receive_Title = "Receive.Title"
    case Receive_YourTonAddress = "Receive.YourTonAddress"
    case Receive_YourTronAddress = "Receive.YourTronAddress"
    case Receive_TonDisclaimer = "Receive.TonDisclaimer"
    case Receive_TronDisclaimer = "Receive.TronDisclaimer"
    case Receive_CopyAddress = "Receive.CopyAddress"
    case Receive_ShareQRCode = "Receive.ShareQRCode"
    case Receive_BuyCrypto = "Receive.BuyCrypto"
    case Receive_BuyWithCard = "Receive.BuyWithCard"
    case Receive_BuyWithCrypto = "Receive.BuyWithCrypto"
    case Receive_AddressCopied = "Receive.AddressCopied"
    case Receive_BuyNotSupportedOnTestnet = "Receive.BuyNotSupportedOnTestnet"

    case Time_Today = "Time.Today"

    case TransactionInfo_SendingTitle = "TransactionInfo.SendingTitle"
    case TransactionInfo_SentTitle = "TransactionInfo.SentTitle"
    case TransactionInfo_ReceivedTitle = "TransactionInfo.ReceivedTitle"
    case TransactionInfo_SwapTitle_Completed = "TransactionInfo.SwapTitle.Completed"
    case TransactionInfo_SwapTitle_Pending = "TransactionInfo.SwapTitle.Pending"
    case TransactionInfo_SwapTitle_Failed = "TransactionInfo.SwapTitle.Failed"
    case TransactionInfo_SwapTitle_Expired = "TransactionInfo.SwapTitle.Expired"
    case TransactionInfo_SentTo = "TransactionInfo.SentTo"
    case TransactionInfo_ReceivedFrom = "TransactionInfo.ReceivedFrom"
    case TransactionInfo_ExchangeRate = "TransactionInfo.ExchangeRate"
    case TransactionInfo_ChangellyPaymentAddress = "TransactionInfo.ChangellyPaymentAddress"
    case TransactionInfo_Comment = "TransactionInfo.Comment"
    case TransactionInfo_Details = "TransactionInfo.Details"
    case TransactionInfo_SenderAddress = "TransactionInfo.SenderAddress"
    case TransactionInfo_Recipient = "TransactionInfo.Recipient"
    case TransactionInfo_Amount = "TransactionInfo.Amount"
    case TransactionInfo_Fee = "TransactionInfo.Fee"
    case TransactionInfo_ViewInExplorer = "TransactionInfo.ViewInExplorer"
    case TransactionInfo_OnFragment = "TransactionInfo.OnFragment"
    case TransactionInfo_ReceivedNFT = "TransactionInfo.ReceivedNFT"
    case TransactionInfo_EncryptedComment = "TransactionInfo.EncryptedComment"
    case TransactionInfo_Decrypt = "TransactionInfo.Decrypt"
    case TransactionInfo_Repeat = "TransactionInfo.Repeat"
    case TransactionInfo_TxIdCopied = "TransactionInfo.TxIdCopied"
    
    case SendCurrency_ChooseCurrency = "SendCurrency.ChooseCurrency"
    
    case Send_Title = "Send.Title"
    case Send_SendTo = "Send.SendTo"
    case Send_AddressOrDomain = "Send.AddressOrDomain"
    case Send_Paste = "Send.Paste"
    case Send_UnsupportedAddress = "Send.UnsupportedAddress"
    case Send_Amount = "Send.Amount"
    case Send_Max = "Send.Max"
    case Send_Fee = "Send.Fee"
    case Send_CommentOrMemo = "Send.CommentOrMemo"
    case Send_EncryptedComment = "Send.EncryptedComment"
    case Send_MemoReqired = "Send.MemoRequired"
    case Send_ClipboardEmpty = "Send.ClipboardEmpty"
    case Send_AuthorizeDiesel = "Send.AuthorizeDiesel"
    case Send_PricelessTokenTransferWarning = "Send.PricelessTokenTransferWarning"
    case Send_NotSupportedForReadonly = "Send.NotSupportedForReadonly"
    
    case Send_Confirm_CopyAddress = "Send.Confirm.CopyAddress"
    case Send_Confirm_Title = "Send.Confirm.Title"
    case Send_Confirm_AddToAddressBook = "Send.Confirm.AddToAddressBook"
    case Send_Confirm_OpenInExplorer = "Send.Confirm.OpenInExplorer"
    case Send_Confirm_Yes = "Send.Confirm.Yes"
    case Send_Confirm_NoEdit = "Send.Confirm.NoEdit"
    
    case SendTo_Title = "SendTo.Title"
    case SendTo_To = "SendTo.To"
    case SendTo_SendTo = "SendTo.SendTo"
    case SendTo_AddressOrDomain = "SendTo.AddressOrDomain"
    case SendTo_Recent = "SendTo.Recent"
    case SendTo_Wallet = "SendTo.Wallet"

    case SendAmount_Title = "SendAmount.Title"
    case SendAmount_Continue = "SendAmount.Continue"
    case SendAmount_InsufficientBalance = "SendAmount.InsufficientBalance"
    case SendAmount_Warning = "SendAmount.Warning"
    case SendAmount_SendingImportantToken = "SendAmount.SendingImportantToken"

    case SendConfirm_Title = "SendConfirm.Title"
    case SendConfirm_Message = "SendConfirm.Message"
    case SendConfirm_AddComment = "SendConfirm.AddComment"
    case SendConfirm_EncryptComment = "SendConfirm.EncryptComment"
    case SendConfirm_Details = "SendConfirm.Details"
    case SendConfirm_Recipient = "SendConfirm.Recipient"
    case SendConfirm_RecipientAddress = "SendConfirm.RecipientAddress"
    case SendConfirm_Amount = "SendConfirm.Amount"
    case SendConfirm_Fee = "SendConfirm.Fee"
    case SendConfirm_Confirm = "SendConfirm.Confirm"
    case SendConfirm_ConfirmSend = "SendConfirm.ConfirmSend"
    case SendConfirm_ConfirmAmountAndAddress = "SendConfirm.ConfirmAmountAndAddress"
    
    case SwitchAccount_Add = "SwitchAccount.Add"
    case SwitchAccount_CreateNewWallet = "SwitchAccount.CreateNewWallet"
    case SwitchAccount_ImportWallet = "SwitchAccount.ImportWallet"
    case SwitchAccount_LedgerConnect = "SwitchAccount.LedgerConnect"
    case SwitchAccount_Cancel = "SwitchAccount.Cancel"
    
    case Sent_CoinsSentTo = "Sent.CoinsSentTo"
    case Sent_Details = "Sent.Details"
    case Sent_Close = "Sent.Close"

    case Send_NFT_Title = "Send.NFT.Title"
    case Send_NFT_Confirm = "Send.NFT.Confirm"
    case Send_NFT_AssetsHeader = "Send.NFT.AssetsHeader"
    case Send_Burn_Title = "Send.Burn.Title"
    case Send_Burn_Confirm = "Send.Burn.Confirm"
    
    case Swap_Title = "Swap.Title"
    case Swap_YouSell = "Swap.YouSell"
    case Swap_YouBuy = "Swap.YouBuy"
    case Swap_Max = "Swap.Max"
    case Swap_Details = "Swap.Details"
    case Swap_PricePer = "Swap.PricePer"
    case Swap_BlockchainFee = "Swap.BlockchainFee"
    case Swap_RoutingFees = "Swap.RoutingFees"
    case Swap_RoutingFeesInfo = "Swap.RoutingFeesInfo"
    case Swap_Included = "Swap.Included"
    case Swap_PriceImpact = "Swap.PriceImpact"
    case Swap_PriceImpactInfo = "Swap.PriceImpactInfo"
    case Swap_MinimumReceived = "Swap.MinimumReceived"
    case Swap_MinimumReceivedInfo = "Swap.MinimumReceivedInfo"
    case Swap_EnterAmounts = "Swap.EnterAmounts"
    case Swap_Submit = "Swap.Submit"
    case Swap_Unavailable = "Swap.Unavailable"
    case Swap_Minimum = "Swap.Minimum"
    case Swap_Maximum = "Swap.Maximum"
    case Swap_InsufficientBalance = "Swap.InsufficientBalance"
    case Swap_Confirm = "Swap.Confirm"
    case Swap_ConfirmSubtitle = "Swap.ConfirmSubtitle"
    case Swap_InvalidPair = "Swap.InvalidPair"
    case Swap_Continue = "Swap.Continue"
    case Swap_CrossChainSwapBy = "Swap.CrossChainSwapBy"
    case Swap_CrossChainDetails = "Swap.CrossChainDetails"
    case Swap_CrossChainHighlights = "Swap.CrossChainHighlights"
    case Swap_CrossChainHighlightLinks = "Swap.CrossChainHighlightLinks"
    case Swap_AuthorizeDiesel = "Swap.AuthorizeDiesel"
    case Swap_DieselPendingPrevious = "Swap.DieselPendingPrevious"
    case Swap_NotSupportedOnAccount = "Swap.NotSupportedOnAccount"

    case SwapToken_YouSell = "SwapToken.YouSell"
    case SwapToken_YouBuy = "SwapToken.YouBuy"
    case SwapToken_MyAssets = "SwapToken.MyAssets"
    case SwapToken_Popular = "SwapToken.Popular"
    case SwapToken_All = "SwapToken.All"
    
    case CrossChainSwap_Swapping = "CrossChainSwap_Swapping"
    case CrossChainSwap_ReceiveTo = "CrossChainSwap.ReceiveTo"
    case CrossChainSwap_EnterChainAddress = "CrossChainSwap.EnterChainAddress"
    case CrossChainSwap_Paste = "CrossChainSwap.Paste"
    case CrossChainSwap_FromTonDescription = "CrossChainSwap.FromTonDescription"
    case CrossChainSwap_EnterReceivingAddress = "CrossChainSwap.EnterReceivingAddress"
    case CrossChainSwap_SendToThisAddress = "CrossChainSwap.SendToThisAddress"
    case CrossChainSwap_ShowQR = "CrossChainSwap.ShowQR"
    case CrossChainSwap_HideQR = "CrossChainSwap.HideQR"
    case CrossChainSwap_ToTonDescription = "CrossChainSwap.ToTonDescription"
    case CrossChainSwap_ToTonDescriptionHighlights = "CrossChainSwap.ToTonDescriptionHighlights"
    case CrossChainSwap_ToTonDescriptionHighlightLinks = "CrossChainSwap.ToTonDescriptionHighlightLinks"
    case CrossChainSwap_TransactionID = "CrossChainSwap.TransactionID"
    case CrossChainSwap_TransactionIDCopied = "CrossChainSwap.TransactionIDCopied"
    case CrossChainSwap_WaitingForPayment = "CrossChainSwap.WaitingForPayment";
    
    case Earn_Title = "Earn.Title"
    case Earn_YourStakingBalance = "Earn.YourStakingBalance"
    case Earn_UnstakeRequestInfo = "Earn.UnstakeRequestInfo"
    case Earn_AddStake = "Earn.AddStake"
    case Earn_Unstake = "Earn.Unstake"
    case Earn_History = "Earn.History"
    case Earn_Earned = "Earn.Earned"
    case Earn_Unstaked = "Earn.Unstaked"
    case Earn_Staked = "Earn.Staked"
    case Earn_Staking = "Earn.Staking"
    case Earn_UnstakeRequest = "Earn.UnstakeRequest"
    case Earn_EarnWhileHolding = "Earn.EarnWhileHolding"
    case Earn_EstimatedAPY = "Earn.EstimatedAPY"
    case Earn_WhyThisIsSafe = "Earn.WhyThisIsSafe"
    case Earn_WhyStakingIsSafe = "Earn.WhyStakingIsSafe"
    case Earn_WhyStakingIsSafeDesc = "Earn.WhyStakingIsSafeDesc"
    case Earn_NotSupportedOnTestnet = "Earn.NotSupportedOnTestnet"
    
    case Staking_AddStake = "Staking.AddStake"
    case Staking_Unstake = "Staking.Unstake"
    case Staking_StakingBalance = "Staking.StakingBalance"
    case Staking_EstimatedBalanceInAYear = "Staking.EstimatedBalanceInAYear"
    case Staking_UseAll = "Staking.UseAll"
    case Staking_StakeTON = "Staking.StakeTON"
    case Staking_UnstakeTON = "Staking.UnstakeTON"
    case Staking_StakeMY = "Staking.StakeMY"
    case Staking_UnstakeMY = "Staking.UnstakeMY"
    case Staking_ConfirmAddStake = "Staking.ConfirmAddStake"
    case Staking_ConfirmUnstake = "Staking.ConfirmUnstake"
    case Staking_InsufficientTONBalance = "Staking.InsufficientTONBalance"
    case Staking_InsufficientStakedBalance = "Staking.InsufficientStakedBalance"
    case Staking_InsufficientBalance = "Staking.InsufficientBalance"
    case Staking_InsufficientMinAmount = "Staking.InsufficientMinAmount"
    case Staking_InsufficientFeeAmount = "Staking.InsufficientFeeAmount"
    case Staking_ConfirmStake_Title = "Staking.ConfirmStake.Title"
    case Staking_ConfirmStake_Hint = "Staking.ConfirmStake.Hint"
    case Staking_ConfirmUnstake_Title = "Staking.ConfirmUnstake.Title"
    case Staking_ConfirmUnstake_Hint = "Staking.ConfirmUnstake.Hint"
    
    case StakeUnstake_StakingDetails = "StakeUnstake.StakingDetails"
    case StakeUnstake_UnstakingDetails = "StakeUnstake.UnstakingDetails"
    case StakeUnstake_CurrentAPY = "StakeUnstake.CurrentAPY"
    case StakeUnstake_EstimatedEarningPerYear = "StakeUnstake.EstimatedEarningPerYear"
    case StakeUnstake_ReceivingLabel = "StakeUnstake.ReceivingLabel"
    case StakeUnstake_ReceivingInfo_Instantly = "StakeUnstake.ReceivingInfo.Instantly"
    case StakeUnstake_InstantWithdrawalLabel = "StakeUnstake.InstantWithdrawalLabel"
    case StakeUnstake_InstantWithdrawalInfo = "StakeUnstake.InstantWithdrawalInfo"
    
    
    case QRScan_Title = "QRScan.Title"
    case QRScan_Back = "QRScan.Back"
    case QRScan_NoAccessTitle = "QRScan.NoAccessTitle"
    case QRScan_NoAccessCamera = "QRScan.NoAccessCamera"
    case QRScan_NoAccessOpenSettings = "QRScan.NoAccessOpenSettings"
    case QRScan_NoValidQRDetected = "QRScan.NoValidQRDetected"
        
    case Tokens_Title = "Tokens.Title"

    case Token_Price = "Token.Price"
    case Token_Day = "Token.Day"
    case Token_Week = "Token.Week"
    case Token_Month = "Token.Month"
    case Token_ThreeMonths = "Token.ThreeMonths"
    case Token_Year = "Token.Year"
    case Token_All = "Token.All"
    case Token_NoTransactions = "Token.NoTransactions"
    
    case Assets_Title = "Assets.Title"
    case Assets_NoAssetsFound = "Assets.NoAssetsFound"
    case Assets_Search = "Assets.Search"
    
    case Explore_Title = "Explore.Title"

    case Connected_Title = "Connected.Title"

    case Settings_Title = "Settings.Title"
    case Settings_YourAddress = "Settings.YourAddress"
    case Settings_Edit = "Settings.Edit"
    case Settings_ChangeAvatar = "Settings.ChangeAvatar"
    case Settings_EditWalletName = "Settings.EditWalletName"
    case Settings_AddAccount = "Settings.AddAccount"
    case Settings_Appearance = "Settings.Appearance"
    case Settings_AssetsAndActivity = "Settings.AssetsAndActivity"
    case Settings_ConnectedApps = "Settings.ConnectedApps"
    case Settings_Language = "Settings.Language"
    case Settings_Backup = "Settings.Backup"
    case Settings_WalletVersions = "Settings.WalletVersions"
    case Settings_QuestionAndAnswers = "Settings.QuestionAndAnswers"
    case Settings_Terms = "Settings.Terms"
    case Settings_SwitchToCapacitor = "Settings.SwitchToCapacitor"
    case Settings_SignOut = "Settings.SignOut"
    case Settings_DeleteWallet = "Settings.DeleteWallet"
    case Settings_DeleteWalletTitle = "Settings.DeleteWalletTitle"
    case Settings_DeleteWalletInfo = "Settings.DeleteWalletInfo"

    case Appearance_ColorTheme = "Appearance.ColorTheme"
    case Appearance_NightMode = "Appearance.NightMode"
    case Appearance_System = "Appearance.System"
    case Appearance_Light = "Appearance.Light"
    case Appearance_Dark = "Appearance.Dark"
    case Appearance_AppIcon = "Appearance.AppIcon"
    case Appearance_OtherSettings = "Appearance.OtherSettings"
    case Appearance_Animations = "Appearance.Animations"
    case Appearance_Sounds = "Appearance.Sounds"
    
    case NightMode_Title = "NightMode.Title"
    
    case InAppBrowser_Reload = "InAppBrowser.Reload"
    case InAppBrowser_OpenInSafari = "InAppBrowser.OpenInSafari"
    case InAppBrowser_CopyURL = "InAppBrowser.CopyURL"
    case InAppBrowser_Share = "InAppBrowser.Share"

    case Asset_Title = "Asset.Title"
    case Asset_Description = "Asset.Description"
    case Asset_ViewInExplorer = "Asset.ViewInExplorer"
    case Asset_Send = "Asset.Send"
    case Asset_Burn = "Asset.Burn"
    case Asset_StandaloneNFT = "Asset.StandaloneNFT"
    case Asset_LinkDomain = "Asset.LinkDomain"
    case Asset_UnlinkDomainFrom = "Asset.UnlinkDomainFrom"
    case Asset_UseCard = "Asset.UseCard"
    case Asset_ResetCard = "Asset.ResetCard"
    case Asset_UsePalette = "Asset.UsePalette"
    case Asset_ResetPalette = "Asset.ResetPalette"
    
    case AssetsAndActivity_Title = "AssetsAndActivity.Title"
    case AssetsAndActivity_BaseCurrency = "AssetsAndActivity.BaseCurrency"
    case AssetsAndActivity_HideTinyTransfers = "AssetsAndActivity.HideTinyTransfers"
    case AssetsAndActivity_HideTinyTransfersHint = "AssetsAndActivity.HideTinyTransfersHint"
    case AssetsAndActivity_HideNoCostTokens = "AssetsAndActivity.HideNoCostTokens"
    case AssetsAndActivity_HideNoCostTokensHint = "AssetsAndActivity.HideNoCostTokensHint"
    case AssetsAndActivity_YourTokens = "AssetsAndActivity.YourTokens"
    case AssetsAndActivity_AddToken = "AssetsAndActivity.AddToken"
    
    case BaseCurrency_Title = "BaseCurrency.Title"
    case BaseCurrency_MainCurrency = "BaseCurrency.MainCurrency"
    case BaseCurrency_USD = "BaseCurrency.USD"
    case BaseCurrency_USDName =  "BaseCurrency.USDName"
    case BaseCurrency_EUR = "BaseCurrency.EUR"
    case BaseCurrency_EURName = "BaseCurrency.EURName"
    case BaseCurrency_RUB = "BaseCurrency.RUB"
    case BaseCurrency_RUBName = "BaseCurrency.RUBName"
    case BaseCurrency_CNY = "BaseCurrency.CNY"
    case BaseCurrency_CNYName = "BaseCurrency.CNYName"
    case BaseCurrency_BTC = "BaseCurrency.BTC"
    case BaseCurrency_BTCName = "BaseCurrency.BTCName"
    case BaseCurrency_TON = "BaseCurrency.TON"
    case BaseCurrency_TONName = "BaseCurrency.TONName"
    
    case Language_Title = "Language.Title"
    case Language_InterfaceLanguage = "Language.InterfaceLanguage"
    
    case WalletVersions_Title = "WalletVersions.Title"
    case WalletVersions_Current = "WalletVersions.Current"
    case WalletVersions_OtherVersions = "WalletVersions.OtherVersions"
    case WalletVersions_Hint = "WalletVersions.Hint"

    case ConnectDapp_Hint = "ConnectDapp.Hint"
    case ConnectDapp_Connect = "ConnectDapp.Connect"
    case ConnectDapp_Confirm = "ConnectDapp.Confirm"
    
    case TonConnect_ReceivingAddress = "TonConnect.ReceivingAddress"
    case TonConnect_ShowMore = "TonConnect.ShowMore"
    case TonConnect_Payload = "TonConnect.Payload"
    case TonConnect_StateInit = "TonConnect.StateInit"
    
    case ConnectedApps_Title = "ConnectedApps.Title"
    case ConnectedApps_ConnectedApps = "ConnectedApps.ConnectedApps"
    case ConnectedApps_DisconnectAll = "ConnectedApps.DisconnectAll"
    case ConnectedApps_DisconnectAllConfirm = "ConnectedApps.DisconnectAllConfirm"
    case ConnectedApps_DisconnectAllConfirmText = "ConnectedApps.DisconnectAllConfirmText"
    case ConnectedApps_Disconnect = "ConnectedApps.Disconnect"
    case ConnectedApps_Empty = "ConnectedApps.Empty"

    case ChooseWallet_Title = "ChooseWallet.Title"
    case ChooseWallet_Hint = "ChooseWallet.Hint"
    
    case Error_Title = "Error.Title"
    case Error_InvalidAmount = "Error.InvalidAmount"
    case Error_InvalidAddress = "Error.InvalidAddress"
    case Error_InsufficientBalance = "Error.InsufficientBalance"
    case Error_DomainNotResolved = "Error.DomainNotResolved"
    case Error_WalletNotInitialized = "Error.WalletNotInitialized"
    case Error_InvalidAddressFormat = "Error.InvalidAddressFormat"
    case Error_PartialTransactionFailure = "Error.PartialTransactionFailure"
    case Error_IncorrectDeviceTime = "Error.IncorrectDeviceTime"
    case Error_UnsuccesfulTransfer = "Error.UnsuccesfulTransfer"
    case Error_UnsupportedHardwareOperation = "Error.UnsupportedHardwareOperation"
    case Error_EncryptedDataNotSupported = "Error.EncryptedDataNotSupported"
    case Error_UnsupportedHardwareNftOperation = "Error.UnsupportedHardwareNftOperation"
    case Error_UnsupportedHardwareContract = "Error.UnsupportedHardwareContract"
    case Error_NonAsciiCommentForHardwareOperation = "Error.NonAsciiCommentForHardwareOperation"
    case Error_TooLongCommentForHardwareOperation = "Error.TooLongCommentForHardwareOperation"
    case Error_UnsupportedHardwarePayload = "Error.UnsupportedHardwarePayload"
    case Error_ServerError = "Error.ServerError"
    case Error_NetworkError = "Error.NetworkError"
    case Error_DebugError = "Error.DebugError"
    case Error_Unexpected = "Error.Unexpected"

    case HardwareNotSupported_Title = "HardwareNotSupported.Title"
    case HardwareNotSupported_Text = "HardwareNotSupported.Text"
    case HardwareNotSupported_Switch = "HardwareNotSupported.Switch"
    
    public static var bundle: Bundle = Bundle(path: AirBundle.path(forResource: "en", ofType: "lproj")!)!
    public var localized: String {
        return NSLocalizedString(rawValue, bundle: WStrings.bundle, comment: "")
    }

    public static func WordCheck_ViewWords(wordIndices: [Int]) -> String {
        return fillValues(lang("Let’s check that you wrote them down correctly. Please enter the words\n%1$@, %2$@ and %3$@."), values: wordIndices.map({ i in
            return "\(i + 1)"
        }))
    }

    public static func SetPasscode_Text(digits: Int) -> String {
        return fillValues(lang("Enter the %1$@ digits in the passcode."), values: ["\(digits)"])
    }
    public static func ConfirmPasscode_Text(digits: Int) -> String {
        return fillValues(lang("Re-enter the %1$@ digits in the passcode."), values: ["\(digits)"])
    }
    
    public static func InsufficientBalance_Text(symbol: String) -> String {
        return fillValues(lang("Insufficient %1$@ Balance"), values: [symbol])
    }
    
    public static func Send_AuthorizeDiesel_Text(symbol: String) -> String {
        return fillValues(lang("Authorize %1$@ fee"),
                          values: [symbol])
    }
    
    public static func ConfirmAmountAndAddress_Text(amountString: String, address: String) -> String {
        return fillValues(lang("%1$@ to %2$@"),
                          values: [amountString, address])
    }
    
    public static func Swap_PricePer_Text(symbol: String) -> String {
        return fillValues(lang("Price per 1 %1$@"),
                          values: [symbol])
    }
    
    public static func Swap_InsufficientBalance_Text(symbol: String) -> String {
        return fillValues(lang("Insufficient %1$@ Balance"),
                          values: [symbol])
    }
    
    public static func Swap_Submit_Text(from: String, to: String) -> String {
        return fillValues(lang("Swap %1$@ to %2$@"),
                          values: [from, to])
    }

    public static func Swap_ConfirmSubtitle_Text(from: String, to: String) -> String {
        return fillValues(lang("%1$@ to %2$@"),
                          values: [from, to])
    }
    
    public static func Swap_AuthorizeDiesel_Text(symbol: String) -> String {
        return fillValues(lang("Authorize %1$@ fee"),
                          values: [symbol])
    }
    
    public static func CrossChainSwap_EnterChainAddress_Text(symbol: String) -> String {
        return fillValues(lang("Enter %1$@ address"), values: [symbol])
    }
    
    public static func CrossChainSwap_SendToThisAddress_Text(symbol: String) -> String {
        return fillValues(lang("SEND %1$@ TO THIS ADDRESS"), values: [symbol])
    }
        
    public static func Earn_UnstakeRequestInfo_Text(remainingTime: String) -> String {
        return fillValues(lang("You will receive your unstaked deposit \nin %1$@."),
                          values: [remainingTime])
    }
    
    public static func Staking_InsufficientMinAmount_Text(amount: Double) -> String {
        return fillValues(lang("Minimum %1$@ TON"),
                          values: [String(amount)])
    }

    public static func Staking_InsufficientFeeAmount_Text(amount: Double) -> String {
        return fillValues(lang("Insufficient fee: %1$@ TON"),
                          values: [String(amount)])
    }

    public static func fillValues(_ format: String, values: [String]) -> String {
        var result = format
        for (index, value) in values.enumerated() {
            result = result.replacingOccurrences(of: "%\(index + 1)$@", with: value)
        }
        return result
    }

    private static func fillValues(_ format: String,
                                   textAttr: [NSAttributedString.Key: Any],
                                   values: [NSAttributedString]) -> NSMutableAttributedString {
        var formatString = format
        let result = NSMutableAttributedString()
        for (index, value) in values.enumerated() {
            if let valueRange = formatString.range(of: "%\(index + 1)$@") {
                // the string before format value
                let stringBeforeValue = String(formatString[..<valueRange.lowerBound])
                formatString = String(formatString[valueRange.upperBound...])
                result.append(NSAttributedString(string: String(stringBeforeValue)))
                // value
                result.append(value)
            }
        }
        return result
    }

}
