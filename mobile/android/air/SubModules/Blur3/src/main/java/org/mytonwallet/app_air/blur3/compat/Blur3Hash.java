package org.mytonwallet.app_air.blur3.compat;

/** Blur3 port: the hash step Telegram keeps in {@code MediaDataController.calcHash}. */
public final class Blur3Hash {

    private Blur3Hash() {}

    public static long calcHash(long hash, long id) {
        hash ^= hash >>> 21;
        hash ^= hash << 35;
        hash ^= hash >>> 4;
        return hash + id;
    }
}
