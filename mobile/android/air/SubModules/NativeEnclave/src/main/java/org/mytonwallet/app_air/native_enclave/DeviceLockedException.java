package org.mytonwallet.app_air.native_enclave;

public class DeviceLockedException extends Exception {

    public static final String ERROR_CODE = "DeviceLocked";

    public DeviceLockedException() {
        super(ERROR_CODE);
    }

    public DeviceLockedException(Throwable cause) {
        super(ERROR_CODE, cause);
    }

    public static boolean matches(String error) {
        return error != null && error.contains(ERROR_CODE);
    }
}
