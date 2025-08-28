#include <jni.h>
#include <cmath>
#include <android/bitmap.h>
#include <vector>

extern "C" {

std::vector<std::pair<float, float>> gatherPositions(std::vector<std::pair<float, float>> list, int phase) {
    std::vector<std::pair<float, float>> result(4);
    for (int i = 0; i < 4; i++) {
        int pos = phase + i * 2;
        while (pos >= 8) {
            pos -= 8;
        }
        result[i] = list[pos];
        result[i].second = 1.0f - result[i].second;
    }
    return result;
}

thread_local static float *pixelCache = nullptr;
thread_local static int pixelCacheSize = 0;

JNIEXPORT void Java_org_mytonwallet_n_utils_NativeUtilities_generateGradient(JNIEnv *env, jclass clazz, jobject bitmap, jboolean unpin, jint phase, jfloat progress, jint width, jint height, jint stride, jintArray colors) {
    if (!bitmap) {
        return;
    }

    if (!width || !height) {
        return;
    }

    uint8_t *pixels = nullptr;
    if (AndroidBitmap_lockPixels(env, bitmap, (void **) &pixels) < 0) {
        return;
    }

    std::vector<std::pair<float, float>> positions{
            {0.80f, 0.10f},
            {0.60f, 0.20f},
            {0.35f, 0.25f},
            {0.25f, 0.60f},
            {0.20f, 0.90f},
            {0.40f, 0.80f},
            {0.65f, 0.75f},
            {0.75f, 0.40f}
    };

    int32_t previousPhase = phase + 1;
    if (previousPhase > 7) {
        previousPhase = 0;
    }
    std::vector<std::pair<float, float>> previous = gatherPositions(positions, previousPhase);
    std::vector<std::pair<float, float>> current = gatherPositions(positions, phase);

    auto colorsArray = (uint8_t *) env->GetIntArrayElements(colors, nullptr);
    float *newPixelCache = nullptr;

    if (width * height != pixelCacheSize && pixelCache != nullptr) {
        delete[] pixelCache;
        pixelCache = nullptr;
    }
    pixelCacheSize = width * height;

    if (pixelCache == nullptr) {
        newPixelCache = new float[width * height * 2];
    }
    float directPixelY;
    float centerDistanceY;
    float centerDistanceY2;
    int32_t colorsCount = colorsArray[12] == 0 && colorsArray[13] == 0 && colorsArray[14] == 0 && colorsArray[15] == 0 ? 3 : 4;

    for (int y = 0; y < height; y++) {
        if (pixelCache == nullptr) {
            directPixelY = (float) y / (float) height;
            centerDistanceY = directPixelY - 0.5f;
            centerDistanceY2 = centerDistanceY * centerDistanceY;
        }
        uint32_t offset = y * stride;
        for (int x = 0; x < width; x++) {
            float pixelX;
            float pixelY;
            if (pixelCache != nullptr) {
                pixelX = pixelCache[(y * width + x) * 2];
                pixelY = pixelCache[(y * width + x) * 2 + 1];
            } else {
                float directPixelX = (float) x / (float) width;

                float centerDistanceX = directPixelX - 0.5f;
                float centerDistance = sqrtf(centerDistanceX * centerDistanceX + centerDistanceY2);

                float swirlFactor = 0.35f * centerDistance;
                float theta = swirlFactor * swirlFactor * 0.8f * 8.0f;
                float sinTheta = sinf(theta);
                float cosTheta = cosf(theta);

                pixelX = newPixelCache[(y * width + x) * 2] = std::max(0.0f, std::min(1.0f, 0.5f + centerDistanceX * cosTheta - centerDistanceY * sinTheta));
                pixelY = newPixelCache[(y * width + x) * 2 + 1] = std::max(0.0f, std::min(1.0f, 0.5f + centerDistanceX * sinTheta + centerDistanceY * cosTheta));
            }

            float distanceSum = 0.0f;

            float r = 0.0f;
            float g = 0.0f;
            float b = 0.0f;

            for (int i = 0; i < colorsCount; i++) {
                float colorX = previous[i].first + (current[i].first - previous[i].first) * progress;
                float colorY = previous[i].second + (current[i].second - previous[i].second) * progress;

                float distanceX = pixelX - colorX;
                float distanceY = pixelY - colorY;

                float distance = std::max(0.0f, 0.9f - sqrtf(distanceX * distanceX + distanceY * distanceY));
                distance = distance * distance * distance * distance;
                distanceSum += distance;

                r = r + distance * ((float) colorsArray[i * 4] / 255.0f);
                g = g + distance * ((float) colorsArray[i * 4 + 1] / 255.0f);
                b = b + distance * ((float) colorsArray[i * 4 + 2] / 255.0f);
            }

            pixels[offset + x * 4] = (uint8_t) (b / distanceSum * 255.0f);
            pixels[offset + x * 4 + 1] = (uint8_t) (g / distanceSum * 255.0f);
            pixels[offset + x * 4 + 2] = (uint8_t) (r / distanceSum * 255.0f);
            pixels[offset + x * 4 + 3] = 0xff;
        }
    }
    if (newPixelCache != nullptr) {
        delete [] pixelCache;
        pixelCache = newPixelCache;
    }

    env->ReleaseIntArrayElements(colors, (jint *) colorsArray, JNI_ABORT);

    if (unpin) {
        AndroidBitmap_unlockPixels(env, bitmap);
    }
}

}