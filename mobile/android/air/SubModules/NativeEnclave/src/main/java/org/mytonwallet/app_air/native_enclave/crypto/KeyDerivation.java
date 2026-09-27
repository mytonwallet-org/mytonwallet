package org.mytonwallet.app_air.native_enclave.crypto;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Arrays;

import javax.crypto.Mac;
import javax.crypto.SecretKey;
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
        byte[] password = passcode.getBytes(StandardCharsets.UTF_8);
        byte[] u = new byte[KEY_LENGTH_BITS / 8];
        byte[] keyBytes = new byte[KEY_LENGTH_BITS / 8];
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(password, "HmacSHA256"));
            mac.update(salt);
            mac.update(new byte[]{0, 0, 0, 1});
            mac.doFinal(u, 0);
            System.arraycopy(u, 0, keyBytes, 0, u.length);
            for (int i = 1; i < PBKDF2_ITERATIONS; i++) {
                mac.update(u);
                mac.doFinal(u, 0);
                for (int j = 0; j < keyBytes.length; j++) {
                    keyBytes[j] ^= u[j];
                }
            }
            return new SecretKeySpec(keyBytes, "AES");
        } finally {
            Arrays.fill(password, (byte) 0);
            Arrays.fill(u, (byte) 0);
            Arrays.fill(keyBytes, (byte) 0);
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
