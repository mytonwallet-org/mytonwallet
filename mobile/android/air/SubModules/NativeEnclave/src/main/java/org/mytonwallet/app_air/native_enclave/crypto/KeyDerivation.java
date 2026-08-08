package org.mytonwallet.app_air.native_enclave.crypto;

import java.security.SecureRandom;

import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;

public class KeyDerivation {

    private static final int SALT_LENGTH = 16;
    private static final int MASTER_KEY_LENGTH = 32;
    private static final int PBKDF2_ITERATIONS = 100_000;
    private static final int KEY_LENGTH_BITS = 256;

    public static byte[] generateSalt() {
        return randomBytes(SALT_LENGTH);
    }

    public static byte[] generateMasterKey() {
        return randomBytes(MASTER_KEY_LENGTH);
    }

    public static SecretKey deriveKeyFromPasscode(String passcode, byte[] salt) throws Exception {
        PBEKeySpec spec = new PBEKeySpec(passcode.toCharArray(), salt, PBKDF2_ITERATIONS, KEY_LENGTH_BITS);
        try {
            SecretKeyFactory factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256");
            byte[] keyBytes = factory.generateSecret(spec).getEncoded();
            return new SecretKeySpec(keyBytes, "AES");
        } finally {
            spec.clearPassword();
        }
    }

    public static SecretKey importMasterKey(byte[] masterKeyBytes) {
        return new SecretKeySpec(masterKeyBytes, "AES");
    }

    private static byte[] randomBytes(int length) {
        byte[] bytes = new byte[length];
        new SecureRandom().nextBytes(bytes);
        return bytes;
    }
}
