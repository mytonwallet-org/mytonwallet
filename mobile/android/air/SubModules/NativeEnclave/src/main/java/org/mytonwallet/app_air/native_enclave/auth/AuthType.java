package org.mytonwallet.app_air.native_enclave.auth;

public enum AuthType {
    PASSCODE("passcode"),
    BIOMETRIC("biometric");

    public final String key;

    AuthType(String key) {
        this.key = key;
    }
}
