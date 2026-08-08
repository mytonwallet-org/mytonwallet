package org.mytonwallet.app_air.native_enclave.storage;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mytonwallet.app_air.native_enclave.auth.AuthType;
import org.mytonwallet.app_air.native_enclave.crypto.HardwareKeyManager;

@RunWith(AndroidJUnit4.class)
public class EnclaveStorageTest {

    private static final String PREFERENCES_NAME = "NativeEnclavePrefs";

    private Context context;
    private EnclaveStorage storage;

    @Before
    public void setUp() {
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        storage = new EnclaveStorage(context);
        clearStorage();
    }

    @After
    public void tearDown() {
        clearStorage();
    }

    @Test
    public void passcodeCredentialRoundTrips() throws Exception {
        byte[] salt = new byte[]{1, 2, 3, 4};
        String wrappedMasterKey = "iv:ciphertext";

        storage.storePasscodeCredential(salt, wrappedMasterKey);

        assertArrayEquals(salt, storage.loadSalt());
        assertEquals(wrappedMasterKey, storage.loadMasterKey(AuthType.PASSCODE));
    }

    @Test
    public void currentVersionRoundTrips() throws Exception {
        assertNull(storage.loadVersion());

        storage.storeCurrentVersion();

        assertEquals(Integer.valueOf(EnclaveStorage.CURRENT_VERSION), storage.loadVersion());
        assertFalse(storage.isLegacyCleanupPending());
    }

    @Test
    public void legacyCleanupPendingIsStoredWithVersion() throws Exception {
        storage.storeCurrentVersionWithLegacyCleanupPending();

        assertEquals(Integer.valueOf(EnclaveStorage.CURRENT_VERSION), storage.loadVersion());
        assertTrue(storage.isLegacyCleanupPending());

        storage.completeLegacyCleanup();

        assertFalse(storage.isLegacyCleanupPending());
    }

    @Test
    public void malformedVersionIsRejected() throws Exception {
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString("state:enclave_version", "invalid")
            .commit();

        try {
            storage.loadVersion();
            fail("Expected malformed version to be rejected");
        } catch (Exception e) {
            assertEquals("Unsupported enclave version: invalid", e.getMessage());
        }
    }

    @Test
    public void clearRemovesVersion() throws Exception {
        storage.storeCurrentVersion();

        storage.clear();

        assertNull(storage.loadVersion());
    }

    private void clearStorage() {
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit();
        HardwareKeyManager.deleteKey();
    }
}
