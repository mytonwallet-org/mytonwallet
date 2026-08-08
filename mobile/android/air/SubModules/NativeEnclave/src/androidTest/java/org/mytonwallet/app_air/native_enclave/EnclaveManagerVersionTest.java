package org.mytonwallet.app_air.native_enclave;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
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
import org.mytonwallet.app_air.native_enclave.storage.EnclaveStorage;

import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public class EnclaveManagerVersionTest {

    private static final String PREFERENCES_NAME = "NativeEnclavePrefs";
    private static final String PREF_VERSION = "state:enclave_version";

    private Context context;

    @Before
    public void setUp() {
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        clearStorage();
    }

    @After
    public void tearDown() {
        clearStorage();
    }

    @Test
    public void legacyMigrationIsAllowedOnlyWithoutVersion() throws Exception {
        EnclaveManager manager = new EnclaveManager(context);

        assertTrue(manager.isLegacyMigrationAllowed());

        new EnclaveStorage(context).storeCurrentVersion();

        assertFalse(manager.isLegacyMigrationAllowed());
    }

    @Test
    public void malformedVersionDisablesLegacyMigration() {
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(PREF_VERSION, "invalid")
            .commit();

        assertFalse(new EnclaveManager(context).isLegacyMigrationAllowed());
    }

    @Test
    public void configuredStorageCannotBeReinitialized() throws Exception {
        EnclaveStorage storage = new EnclaveStorage(context);
        storage.storeCurrentVersion();
        AtomicReference<String> error = new AtomicReference<>();

        new EnclaveManager(context).setupAuth(
            AuthType.PASSCODE,
            "1234",
            null,
            new EnclaveManager.SessionCallback() {
                @Override
                public void onSuccess(String token, long validUntil) {
                    fail("Expected setup to reject configured storage");
                }

                @Override
                public void onError(String value) {
                    error.set(value);
                }
            }
        );

        assertEquals("setupAuth: Authentication is already configured", error.get());
        assertEquals(Integer.valueOf(EnclaveStorage.CURRENT_VERSION), storage.loadVersion());
    }

    @Test
    public void passcodeAuthenticationCanBeReplacedAfterManagerRecreation() {
        EnclaveManager initialManager = new EnclaveManager(context);
        AtomicReference<String> setupToken = new AtomicReference<>();
        AtomicReference<String> setupError = new AtomicReference<>();

        initialManager.setupAuth(
            AuthType.PASSCODE,
            "1234",
            null,
            new EnclaveManager.SessionCallback() {
                @Override
                public void onSuccess(String token, long validUntil) {
                    setupToken.set(token);
                }

                @Override
                public void onError(String value) {
                    setupError.set(value);
                }
            }
        );

        assertNotNull(setupToken.get());
        assertNull(setupError.get());

        EnclaveManager restartedManager = new EnclaveManager(context);
        assertTrue(restartedManager.isPasscodeAuthConfigured());
        restartedManager.reset();

        AtomicReference<String> replacementToken = new AtomicReference<>();
        AtomicReference<String> replacementError = new AtomicReference<>();
        restartedManager.setupAuth(
            AuthType.PASSCODE,
            "5678",
            null,
            new EnclaveManager.SessionCallback() {
                @Override
                public void onSuccess(String token, long validUntil) {
                    replacementToken.set(token);
                }

                @Override
                public void onError(String value) {
                    replacementError.set(value);
                }
            }
        );

        assertNotNull(replacementToken.get());
        assertNull(replacementError.get());

        AtomicReference<String> authorizedToken = new AtomicReference<>();
        restartedManager.authorize(
            AuthType.PASSCODE,
            false,
            "5678",
            null,
            new EnclaveManager.SessionCallback() {
                @Override
                public void onSuccess(String token, long validUntil) {
                    authorizedToken.set(token);
                }

                @Override
                public void onError(String value) {
                    fail("Expected replacement passcode to authorize");
                }
            }
        );

        assertNotNull(authorizedToken.get());
    }

    @Test
    public void operationsRequireConfiguredStorage() {
        try {
            new EnclaveManager(context).duplicateSecret("from", "to");
        } catch (Exception e) {
            assertEquals("Enclave storage is not configured", e.getMessage());
            return;
        }

        fail("Expected operation to reject unconfigured storage");
    }

    @Test
    public void configuredBiometricAuthRequiresCurrentVersionAndStoredCredential() throws Exception {
        EnclaveManager manager = new EnclaveManager(context);
        EnclaveStorage storage = new EnclaveStorage(context);

        storage.storeMasterKey(AuthType.BIOMETRIC, "encrypted-master-key");
        assertFalse(manager.isBiometricAuthConfigured());

        storage.storeCurrentVersion();

        assertTrue(manager.isBiometricAuthConfigured());
        assertEquals(
            "encrypted-master-key",
            storage.loadMasterKey(AuthType.BIOMETRIC)
        );
    }

    private void clearStorage() {
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit();
        HardwareKeyManager.deleteKey();
    }
}
