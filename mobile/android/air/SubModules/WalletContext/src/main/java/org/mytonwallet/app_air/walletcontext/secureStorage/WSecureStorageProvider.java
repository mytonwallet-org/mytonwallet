package org.mytonwallet.app_air.walletcontext.secureStorage;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.SharedPreferences.Editor;
import android.os.Build;
import android.security.KeyChain;
import android.security.KeyPairGeneratorSpec;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyInfo;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import androidx.annotation.Nullable;

import org.mytonwallet.app_air.walletbasecontext.logger.Logger;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.InvalidAlgorithmParameterException;
import java.security.InvalidKeyException;
import java.security.KeyFactory;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.UnrecoverableEntryException;
import java.security.UnrecoverableKeyException;
import java.security.spec.AlgorithmParameterSpec;
import java.security.spec.InvalidKeySpecException;
import java.util.Calendar;
import java.util.GregorianCalendar;
import java.util.Set;

import javax.crypto.BadPaddingException;
import javax.crypto.Cipher;
import javax.crypto.IllegalBlockSizeException;
import javax.crypto.NoSuchPaddingException;
import javax.security.auth.x500.X500Principal;

class WSecureStorageProvider {

    private static final Logger.LogTag LOG_TAG = Logger.LogTag.SECURE_STORAGE;
    private static final String PREFERENCES_FILE = "cap_sec";

    private PasswordStorageImpl passwordStorage;

    public WSecureStorageProvider(Context context) {
        passwordStorage = new PasswordStorageHelper_SDK18();

        boolean isInitialized = false;

        try {
            isInitialized = passwordStorage.init(context);
        } catch (Exception ex) {
            Logger.INSTANCE.e(LOG_TAG, "PasswordStorage initialisation error:" + ex.getMessage());
        }

        if (!isInitialized && passwordStorage instanceof PasswordStorageHelper_SDK18) {
            passwordStorage = new PasswordStorageHelper_SDK16();
            passwordStorage.init(context);
        }
    }

    public void setData(String key, @Nullable String value) {
        setData(key, (value != null ? value : "").getBytes(StandardCharsets.UTF_8));
    }

    public void setData(String key, byte[] data) {
        passwordStorage.setData(key, data);
    }

    public byte[] getData(String key) {
        return passwordStorage.getData(key);
    }

    public String getStringData(String key) {
        byte[] data = getData(key);
        if (data == null)
            return "";
        return new String(data, StandardCharsets.UTF_8);
    }

    public String[] keys() {
        return passwordStorage.keys();
    }

    public void remove(String key) {
        passwordStorage.remove(key);
    }

    public void clear() {
        passwordStorage.clear();
    }

    private interface PasswordStorageImpl {
        boolean init(Context context);

        void setData(String key, byte[] data);

        byte[] getData(String key);

        String[] keys();

        void remove(String key);

        void clear();
    }

    private static class PasswordStorageHelper_SDK16 implements PasswordStorageImpl {
        private SharedPreferences preferences;

        @Override
        public boolean init(Context context) {
            preferences = context.getSharedPreferences(PREFERENCES_FILE, Context.MODE_PRIVATE);
            return true;
        }

        @Override
        public void setData(String key, byte[] data) {
            if (data == null)
                return;
            Editor editor = preferences.edit();
            editor.putString(key, Base64.encodeToString(data, Base64.DEFAULT));
            editor.commit();
        }

        @Override
        public byte[] getData(String key) {
            String res = preferences.getString(key, null);
            if (res == null)
                return null;
            return Base64.decode(res, Base64.DEFAULT);
        }

        @Override
        public String[] keys() {
            Set<String> keySet = preferences.getAll().keySet();
            return keySet.toArray(new String[keySet.size()]);
        }

        @Override
        public void remove(String key) {
            Editor editor = preferences.edit();
            editor.remove(key);
            editor.commit();
        }

        @Override
        public void clear() {
            Editor editor = preferences.edit();
            editor.clear();
            editor.commit();
        }
    }

    private static class PasswordStorageHelper_SDK18 implements PasswordStorageImpl {

        private static final String KEY_ALGORITHM_RSA = "RSA";

        private static final String KEYSTORE_PROVIDER_ANDROID_KEYSTORE = "AndroidKeyStore";
        private static final String RSA_ECB_PKCS1_PADDING = "RSA/ECB/PKCS1Padding";
        private static int KEY_LENGTH = 2048;
        private SharedPreferences preferences;
        private String alias = null;
        private KeyStore ks = null;

        @SuppressLint("TrulyRandom")
        private static String encrypt(PublicKey encryptionKey, byte[] data) throws NoSuchAlgorithmException,
            NoSuchPaddingException, InvalidKeyException, IllegalBlockSizeException, BadPaddingException,
            NoSuchProviderException, InvalidKeySpecException {

            if (data.length <= KEY_LENGTH / 8 - 11) {
                Cipher cipher = Cipher.getInstance(RSA_ECB_PKCS1_PADDING);
                cipher.init(Cipher.ENCRYPT_MODE, encryptionKey);
                byte[] encrypted = cipher.doFinal(data);
                return Base64.encodeToString(encrypted, Base64.DEFAULT);
            } else {
                Cipher cipher = Cipher.getInstance(RSA_ECB_PKCS1_PADDING);
                cipher.init(Cipher.ENCRYPT_MODE, encryptionKey);
                int limit = KEY_LENGTH / 8 - 11;
                int position = 0;
                ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
                while (position < data.length) {
                    if (data.length - position < limit)
                        limit = data.length - position;
                    byte[] tmpData = cipher.doFinal(data, position, limit);
                    try {
                        byteArrayOutputStream.write(tmpData);
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                    position += limit;
                }

                return Base64.encodeToString(byteArrayOutputStream.toByteArray(), Base64.DEFAULT);
            }
        }

        private static byte[] decrypt(PrivateKey decryptionKey, String encryptedData) throws NoSuchAlgorithmException,
            NoSuchPaddingException, InvalidKeyException, IllegalBlockSizeException, BadPaddingException,
            NoSuchProviderException {
            if (encryptedData == null)
                return null;
            byte[] encryptedBuffer = Base64.decode(encryptedData, Base64.DEFAULT);

            if (encryptedBuffer.length <= KEY_LENGTH / 8) {
                Cipher cipher = Cipher.getInstance(RSA_ECB_PKCS1_PADDING);
                cipher.init(Cipher.DECRYPT_MODE, decryptionKey);
                return cipher.doFinal(encryptedBuffer);
            } else {
                Cipher cipher = Cipher.getInstance(RSA_ECB_PKCS1_PADDING);
                cipher.init(Cipher.DECRYPT_MODE, decryptionKey);
                int limit = KEY_LENGTH / 8;
                int position = 0;
                ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
                while (position < encryptedBuffer.length) {
                    if (encryptedBuffer.length - position < limit)
                        limit = encryptedBuffer.length - position;
                    byte[] tmpData = cipher.doFinal(encryptedBuffer, position, limit);
                    try {
                        byteArrayOutputStream.write(tmpData);
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                    position += limit;
                }

                return byteArrayOutputStream.toByteArray();
            }
        }

        @SuppressWarnings("deprecation")
        @SuppressLint({"NewApi", "TrulyRandom"})
        @Override
        public boolean init(Context context) {
            preferences = context.getSharedPreferences(PREFERENCES_FILE, Context.MODE_PRIVATE);
            alias = context.getPackageName() + "_cap_sec";

            try {
                ks = KeyStore.getInstance(KEYSTORE_PROVIDER_ANDROID_KEYSTORE);

                //Use null to load Keystore with default parameters.
                ks.load(null);

                // Check if Private and Public already keys exists. If so we don't need to generate them again
                PrivateKey privateKey = (PrivateKey) ks.getKey(alias, null);
                if (privateKey != null && ks.getCertificate(alias) != null) {
                    PublicKey publicKey = ks.getCertificate(alias).getPublicKey();
                    if (publicKey != null) {
                        // All keys are available.
                        return true;
                    }
                }
            } catch (Exception ex) {
                return false;
            }

            // Create a start and end time, for the validity range of the key pair that's about to be
            // generated.
            Calendar start = new GregorianCalendar();
            Calendar end = new GregorianCalendar();
            end.add(Calendar.YEAR, 10);

            // Specify the parameters object which will be passed to KeyPairGenerator
            AlgorithmParameterSpec spec;
            if (Build.VERSION.SDK_INT < 23) {
                spec = new KeyPairGeneratorSpec.Builder(context)
                    // Alias - is a key for your KeyPair, to obtain it from Keystore in future.
                    .setAlias(alias)
                    // The subject used for the self-signed certificate of the generated pair
                    .setSubject(new X500Principal("CN=" + alias))
                    // The serial number used for the self-signed certificate of the generated pair.
                    .setSerialNumber(BigInteger.valueOf(1337))
                    // Date range of validity for the generated pair.
                    .setStartDate(start.getTime()).setEndDate(end.getTime())
                    .build();
            } else {
                spec = new KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_DECRYPT)
                    .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1)
                    .build();
            }

            // Initialize a KeyPair generator using the the intended algorithm (in this example, RSA
            // and the KeyStore. This example uses the AndroidKeyStore.
            KeyPairGenerator kpGenerator;
            try {
                kpGenerator = KeyPairGenerator.getInstance(KEY_ALGORITHM_RSA, KEYSTORE_PROVIDER_ANDROID_KEYSTORE);
                kpGenerator.initialize(spec);
                // Generate private/public keys
                kpGenerator.generateKeyPair();
            } catch (NoSuchAlgorithmException | InvalidAlgorithmParameterException |
                     NoSuchProviderException e) {
                e.printStackTrace();
            }

            // Check if device support Hardware-backed keystore
            try {
                boolean isHardwareBackedKeystoreSupported;
                if (Build.VERSION.SDK_INT < 23) {
                    isHardwareBackedKeystoreSupported = KeyChain.isBoundKeyAlgorithm(KeyProperties.KEY_ALGORITHM_RSA);
                } else {
                    PrivateKey privateKey = (PrivateKey) ks.getKey(alias, null);
                    KeyChain.isBoundKeyAlgorithm(KeyProperties.KEY_ALGORITHM_RSA);
                    KeyFactory keyFactory = KeyFactory.getInstance(privateKey.getAlgorithm(), "AndroidKeyStore");
                    KeyInfo keyInfo = keyFactory.getKeySpec(privateKey, KeyInfo.class);
                    isHardwareBackedKeystoreSupported = keyInfo.isInsideSecureHardware();
                }
                Logger.INSTANCE.d(LOG_TAG, "Hardware-Backed Keystore Supported: " + isHardwareBackedKeystoreSupported);
            } catch (KeyStoreException | NoSuchAlgorithmException | UnrecoverableKeyException |
                     InvalidKeySpecException | NoSuchProviderException e) {
            }

            return true;
        }

        @Override
        public void setData(String key, byte[] data) {
            try {
                PublicKey publicKey = ks.getCertificate(alias).getPublicKey();

                if (publicKey == null) {
                    Logger.INSTANCE.d(LOG_TAG, "Error: Public key was not found in Keystore");
                    return;
                }

                String value = encrypt(publicKey, data);

                Editor editor = preferences.edit();
                editor.putString(key, value);
                editor.commit();
            } catch (NoSuchAlgorithmException | InvalidKeyException | NoSuchPaddingException
                     | IllegalBlockSizeException | BadPaddingException | NoSuchProviderException
                     | InvalidKeySpecException | KeyStoreException e) {
                e.printStackTrace();
            }
        }

        @Override
        public byte[] getData(String key) {
            try {
                PrivateKey privateKey = (PrivateKey) ks.getKey(alias, null);
                return decrypt(privateKey, preferences.getString(key, null));
            } catch (KeyStoreException | NoSuchAlgorithmException
                     | UnrecoverableEntryException | InvalidKeyException | NoSuchPaddingException
                     | IllegalBlockSizeException | BadPaddingException |
                     NoSuchProviderException e) {
                e.printStackTrace();
            }
            return null;
        }

        @Override
        public String[] keys() {
            Set<String> keySet = preferences.getAll().keySet();
            return keySet.toArray(new String[keySet.size()]);
        }

        @Override
        public void remove(String key) {
            Editor editor = preferences.edit();
            editor.remove(key);
            editor.commit();
        }

        @Override
        public void clear() {
            Editor editor = preferences.edit();
            editor.clear();
            editor.commit();
        }
    }
}
