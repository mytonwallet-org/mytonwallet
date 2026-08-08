package org.mytonwallet.app_air.native_enclave.crypto;

import android.util.Base64;

import java.security.SecureRandom;

import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

public class AesGcm {

    private static final String AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int TAG_LENGTH = 128;
    private static final int IV_LENGTH = 12;

    public static String encrypt(byte[] data, SecretKey key) throws Exception {
        byte[] iv = new byte[IV_LENGTH];
        new SecureRandom().nextBytes(iv);

        Cipher cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION);
        cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_LENGTH, iv));
        byte[] ciphertext = cipher.doFinal(data);

        return Base64.encodeToString(iv, Base64.NO_WRAP)
            + ":" + Base64.encodeToString(ciphertext, Base64.NO_WRAP);
    }

    public static byte[] decrypt(String encrypted, SecretKey key) throws Exception {
        String[] parts = encrypted.split(":", 2);
        byte[] iv = Base64.decode(parts[0], Base64.NO_WRAP);
        byte[] ciphertext = Base64.decode(parts[1], Base64.NO_WRAP);

        Cipher cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION);
        cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_LENGTH, iv));
        return cipher.doFinal(ciphertext);
    }

    public static EncryptedData encryptWithCipher(byte[] data, Cipher cipher) throws Exception {
        byte[] ciphertext = cipher.doFinal(data);
        byte[] iv = cipher.getIV();
        return new EncryptedData(iv, ciphertext);
    }

    public static byte[] decryptWithCipher(byte[] ciphertext, Cipher cipher) throws Exception {
        return cipher.doFinal(ciphertext);
    }

}
