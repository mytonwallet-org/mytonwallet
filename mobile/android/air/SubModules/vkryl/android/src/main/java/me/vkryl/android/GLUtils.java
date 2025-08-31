/*
 * This file is a part of X-Android
 * Copyright © Vyacheslav Krylov 2014
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package me.vkryl.android;

import androidx.annotation.Nullable;

import java.util.concurrent.atomic.AtomicReference;

import javax.microedition.khronos.egl.EGL10;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.egl.EGLContext;
import javax.microedition.khronos.egl.EGLDisplay;
import javax.microedition.khronos.egl.EGLSurface;

/*package-private*/ class GLUtils {

  public interface DisplayCallback {
    void runWithData (EGL10 egl, EGLDisplay display, int[] version);
  }

  public interface ErrorCallback {
    void onError (String message, int eglError);
  }

  public static void withEGLDisplay (DisplayCallback callback, ErrorCallback errorCallback) {
    EGL10 egl = (EGL10) EGLContext.getEGL();
    EGLDisplay display = egl.eglGetDisplay(EGL10.EGL_DEFAULT_DISPLAY);;
    int[] version = new int[2];
    if (display == EGL10.EGL_NO_DISPLAY) {
      onError(errorCallback, "eglGetDisplay failed", egl.eglGetError());
    } else {
      boolean initialized = egl.eglInitialize(display, version);
      if (!initialized) {
        onError(errorCallback, "eglInitialize", egl.eglGetError());
      } else {
        try {
          callback.runWithData(egl, display, version);
        } catch (Throwable t) {
          t.printStackTrace();
        }
      }
    }
    egl.eglTerminate(display);
  }

  private static void onError (ErrorCallback onError, String message, int eglError) {
    if (onError != null) {
      try {
        onError.onError(message, eglError);
      } catch (Throwable t) {
        t.printStackTrace();
      }
    }
  }

  public interface EGLContextCallback {
    void runWithData (EGL10 egl, EGLDisplay display, int[] version, EGLContext context, EGLSurface surface);
  }

  public static void withEGLContext (EGLContextCallback callback, ErrorCallback errorCallback) {
    withEGLDisplay((egl, display, version) -> {
      int[] numConfigs = new int[1];
      EGLConfig[] configs = new EGLConfig[1];
      int[] configAttributes = {
        EGL10.EGL_RENDERABLE_TYPE, 4 /*EGL_OPENGL_ES2_BIT*/,
        EGL10.EGL_NONE
      };
      if (!egl.eglChooseConfig(display, configAttributes, configs, 1, numConfigs)) {
        onError(errorCallback, "eglChooseConfig failed", egl.eglGetError());
        return;
      }
      if (numConfigs[0] <= 0) {
        onError(errorCallback, "eglConfig not initialized", egl.eglGetError());
        return;
      }
      EGLConfig config = configs[0];

      int[] contextAttributes = {
        android.opengl.EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL10.EGL_NONE
      };
      EGLContext context = egl.eglCreateContext(display, config, EGL10.EGL_NO_CONTEXT, contextAttributes);
      if (context == null || context == EGL10.EGL_NO_CONTEXT) {
        onError(errorCallback, "eglCreateContext failed", egl.eglGetError());
      } else {
        int[] surfaceAttributes = new int[] {
          EGL10.EGL_WIDTH, 1,
          EGL10.EGL_HEIGHT, 1,
          EGL10.EGL_NONE
        };
        EGLSurface surface = egl.eglCreatePbufferSurface(display, config, surfaceAttributes);
        if (surface == null || surface == EGL10.EGL_NO_SURFACE) {
          onError(errorCallback, "eglCreatePbufferSurface failed", egl.eglGetError());
        } else {
          boolean applied = egl.eglMakeCurrent(display, surface, surface, context);
          if (!applied) {
            onError(errorCallback, "eglMakeCurrent failed", egl.eglGetError());
          } else {
            try {
              callback.runWithData(egl, display, version, context, surface);
            } catch (Throwable t) {
              t.printStackTrace();
            }
          }
        }
        egl.eglMakeCurrent(display, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_CONTEXT);
        egl.eglDestroySurface(display, surface);
      }
      egl.eglDestroyContext(display, context);
      egl.eglTerminate(display);
    }, errorCallback);
  }

  @Nullable
  public static String fetchGlRenderer () {
    AtomicReference<String> renderer = new AtomicReference<>();
    withEGLContext((egl, display, version, context, surface) -> {
      String result = android.opengl.GLES10.glGetString(android.opengl.GLES10.GL_RENDERER);
      renderer.set(result);
    }, null);
    return renderer.get();
  }
}
