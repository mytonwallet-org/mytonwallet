package org.mytonwallet.app_air.native_enclave.crypto;

import android.util.Base64;

public final class EncryptedData {

        private final byte[] iv;
        private final byte[] ciphertext;

        public EncryptedData(byte[] iv, byte[] ciphertext) {
            this.iv = iv;
            this.ciphertext = ciphertext;
        }

        public byte[] getIv() {
            return iv;
        }

        public byte[] getCiphertext() {
            return ciphertext;
        }

        public String toStorageFormat() {
            return Base64.encodeToString(iv, Base64.NO_WRAP)
                + ":" + Base64.encodeToString(ciphertext, Base64.NO_WRAP);
        }

        public static EncryptedData fromStorageFormat(String stored) {
            String[] parts = stored.split(":", 2);
            byte[] iv = Base64.decode(parts[0], Base64.NO_WRAP);
            byte[] ciphertext = Base64.decode(parts[1], Base64.NO_WRAP);
            return new EncryptedData(iv, ciphertext);
        }
    }
