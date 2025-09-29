export interface AirAppLauncherPlugin {
    switchToAir(): Promise<void>;
    setLanguage(options: {
        langCode: string;
    }): Promise<void>;
    setBaseCurrency(options: {
        currency: string;
    }): Promise<void>;
}
