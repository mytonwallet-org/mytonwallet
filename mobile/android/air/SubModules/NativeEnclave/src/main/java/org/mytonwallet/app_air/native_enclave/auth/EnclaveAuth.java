package org.mytonwallet.app_air.native_enclave.auth;

import androidx.fragment.app.FragmentActivity;

public interface EnclaveAuth {

    void setup(FragmentActivity activity, byte[] masterKey, String passcode, SetupCallback callback);

    void authorize(FragmentActivity activity, String passcode, AuthorizeCallback callback);

    void destroy();

    interface SetupCallback {
        void onSuccess();
        void onError(String error);
    }

    interface AuthorizeCallback {
        void onSuccess(byte[] masterKey);
        void onError(String error);
    }
}
