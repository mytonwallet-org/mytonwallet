package org.mytonwallet.app_air.native_enclave.crypto;

import static org.junit.Assert.assertArrayEquals;

import org.junit.Test;

import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;

public class KeyDerivationTest {

    @Test
    public void matchesStandardPbkdf2WithHmacSha256() throws Exception {
        String[] passcodes = {"1111", "0000", "123456", "9876"};
        for (String passcode : passcodes) {
            byte[] salt = KeyDerivation.generateSalt();
            PBEKeySpec spec = new PBEKeySpec(passcode.toCharArray(), salt, 100_000, 256);
            byte[] expected = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                .generateSecret(spec)
                .getEncoded();

            assertArrayEquals(
                expected,
                KeyDerivation.deriveKeyFromPasscode(passcode, salt).getEncoded()
            );
        }
    }
}
