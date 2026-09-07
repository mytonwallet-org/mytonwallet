package org.mytonwallet.app_air.blur3.compat;

import android.content.res.Resources;

import androidx.annotation.RawRes;

import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/** Blur3 port: replaces {@code ApplicationLoader.applicationContext.getResources()} and {@code AndroidUtilities.readRes}. */
public final class Blur3Resources {

    private Blur3Resources() {}

    public static Resources get() {
        return ApplicationContextHolder.INSTANCE.getApplicationContext().getResources();
    }

    public static String readRaw(@RawRes int rawRes) {
        try (InputStream in = get().openRawResource(rawRes)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int read;
            while ((read = in.read(buffer)) != -1) {
                out.write(buffer, 0, read);
            }
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException("Cannot read raw resource " + rawRes, e);
        }
    }
}
