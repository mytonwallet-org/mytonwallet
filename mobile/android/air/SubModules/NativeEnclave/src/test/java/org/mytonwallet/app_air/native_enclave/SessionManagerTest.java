package org.mytonwallet.app_air.native_enclave;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import org.junit.Test;
import org.mytonwallet.app_air.native_enclave.auth.AuthType;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

public class SessionManagerTest {

    @Test
    public void shortSessionGrantsExactlyItsConfiguredNumberOfUses() throws Exception {
        SessionManager manager = new SessionManager();
        byte[] masterKey = new byte[32];
        SessionManager.SessionResult result =
                manager.createSession(AuthType.PASSCODE, false, 2, masterKey);

        assertArrayEquals(
                masterKey,
                manager.validateSessionAndGetMasterKey(result.token, true)
        );
        assertArrayEquals(
                masterKey,
                manager.validateSessionAndGetMasterKey(result.token, true)
        );

        try {
            manager.validateSessionAndGetMasterKey(result.token, true);
            fail("Expected the short session to be exhausted");
        } catch (Exception expected) {
            assertEquals("Invalid or expired session token", expected.getMessage());
        }
    }

    @Test
    public void concurrentReadsCannotExceedShortSessionBudget() throws Exception {
        SessionManager manager = new SessionManager();
        SessionManager.SessionResult result =
                manager.createSession(AuthType.BIOMETRIC, false, 3, new byte[32]);
        int readerCount = 20;
        ExecutorService executor = Executors.newFixedThreadPool(readerCount);
        CountDownLatch ready = new CountDownLatch(readerCount);
        CountDownLatch start = new CountDownLatch(1);
        AtomicInteger successfulReads = new AtomicInteger();
        List<Future<?>> futures = new ArrayList<>();

        try {
            for (int i = 0; i < readerCount; i++) {
                futures.add(executor.submit(() -> {
                    ready.countDown();
                    start.await();
                    try {
                        manager.validateSessionAndGetMasterKey(result.token, true);
                        successfulReads.incrementAndGet();
                    } catch (Exception ignored) {
                    }
                    return null;
                }));
            }

            ready.await();
            start.countDown();
            for (Future<?> future : futures) {
                future.get();
            }
        } finally {
            executor.shutdownNow();
        }

        assertEquals(3, successfulReads.get());
    }
}
