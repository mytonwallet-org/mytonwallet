package org.mytonwallet.app_air.native_enclave;

import org.mytonwallet.app_air.native_enclave.auth.AuthType;

import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

class SessionManager {

    private static final long LONG_SESSION_DURATION_MS = 5 * 60 * 1000; // 5 min

    private final Map<String, Session> sessions = new HashMap<>();

    static class Session {
        final String token;
        final long validUntil;
        final byte[] masterKey;
        int remainingUsages;

        Session(String token, long validUntil, int remainingUsages, byte[] masterKey) {
            this.token = token;
            this.validUntil = validUntil;
            this.remainingUsages = remainingUsages;
            this.masterKey = masterKey;
        }

        void zeroize() {
            if (masterKey != null) {
                Arrays.fill(masterKey, (byte) 0);
            }
        }
    }

    static class SessionResult {
        final String token;
        final long validUntil;

        SessionResult(String token, long validUntil) {
            this.token = token;
            this.validUntil = validUntil;
        }
    }

    synchronized SessionResult createSession(AuthType authType, boolean isLong, byte[] masterKey) {
        return createSession(authType, isLong, 1, masterKey);
    }

    synchronized SessionResult createSession(AuthType authType, boolean isLong, int usageCount,
                                              byte[] masterKey) {
        String token = authType.key + ":" + randomHex(16);
        long validUntil = isLong ? System.currentTimeMillis() + LONG_SESSION_DURATION_MS : 0;
        sessions.put(token, new Session(token, validUntil, Math.max(usageCount, 1), masterKey));
        return new SessionResult(token, validUntil);
    }

    synchronized byte[] validateSessionAndGetMasterKey(String token, Boolean invalidateShortSession)
            throws Exception {
        Session session = sessions.get(token);
        if (session == null) {
            throw new Exception("Invalid or expired session token");
        }

        long now = System.currentTimeMillis();

        // Long session: valid until expiry
        if (session.validUntil > 0) {
            if (now >= session.validUntil) {
                session.zeroize();
                sessions.remove(token);
                throw new Exception("Session expired");
            }
            return session.masterKey;
        }

        if (session.remainingUsages <= 0) {
            sessions.remove(token);
            throw new Exception("Invalid or expired session token");
        }

        // Short session (validUntil == 0): consume one configured use when requested.
        if (invalidateShortSession) {
            session.remainingUsages -= 1;
            if (session.remainingUsages == 0) {
                sessions.remove(token);
            }
        }

        return session.masterKey;
    }

    synchronized void invalidateShortSession(String token) {
        Session session = sessions.get(token);
        if (session == null || session.validUntil > 0) {
            return;
        }
        session.zeroize();
        sessions.remove(token);
    }

    synchronized void clearAll() {
        for (Session session : sessions.values()) {
            session.zeroize();
        }
        sessions.clear();
    }

    private static String randomHex(int bytes) {
        byte[] buf = new byte[bytes];
        new SecureRandom().nextBytes(buf);
        StringBuilder sb = new StringBuilder(buf.length * 2);
        for (byte b : buf) {
            sb.append(String.format("%02x", b & 0xff));
        }
        return sb.toString();
    }
}
