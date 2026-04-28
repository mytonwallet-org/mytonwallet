package org.mytonwallet.app_air.uicomponents.widgets.particles

object ParticleShaders {

    const val VERTEX_SHADER = """
        attribute vec2 a_startPosition;
        attribute vec2 a_velocity;
        attribute float a_startTime;
        attribute float a_lifetime;
        attribute float a_size;
        attribute float a_baseOpacity;
        attribute vec3 a_color;

        uniform vec2 u_resolution;
        uniform float u_time;
        uniform float u_canvasWidth;
        uniform float u_canvasHeight;
        uniform float u_accelerationFactor;
        uniform float u_fadeInTime;
        uniform float u_fadeOutTime;
        uniform float u_edgeFadeZone;
        uniform mat2 u_rotationMatrices[18];
        uniform vec2 u_spawnCenter;

        varying float v_opacity;
        varying vec3 v_color;

        void main() {
            v_color = a_color;
            float totalAge = u_time - a_startTime;
            float age = mod(totalAge, a_lifetime);

            // For the initial animation, fade in all particles
            float globalFadeIn = min(u_time / u_fadeInTime, 1.0);

            float lifeRatio = age / a_lifetime;

            // Calculate rotation based on completed lifecycles
            float lifecycleCount = floor(totalAge / a_lifetime);
            int rotationIndex = int(mod(lifecycleCount, 18.0));

            // Get rotation matrix
            mat2 rotationMatrix = u_rotationMatrices[rotationIndex];

            // Rotate start position around spawn center
            vec2 startOffset = a_startPosition - u_spawnCenter;
            vec2 rotatedStartOffset = rotationMatrix * startOffset;
            vec2 rotatedStartPosition = u_spawnCenter + rotatedStartOffset;

            // Apply rotation matrix to velocity
            vec2 rotatedVelocity = rotationMatrix * a_velocity;

            // Apply shoot-out effect: fast initial speed that slows down
            float speedMultiplier = 1.0 + u_accelerationFactor * exp(-3.0 * lifeRatio);

            vec2 position = rotatedStartPosition + rotatedVelocity * age * speedMultiplier;

            float opacity = 1.0;
            if (lifeRatio < u_fadeInTime / a_lifetime) {
                opacity = (lifeRatio * a_lifetime) / u_fadeInTime;
            } else if (lifeRatio > 1.0 - u_fadeOutTime / a_lifetime) {
                opacity = (1.0 - lifeRatio) * a_lifetime / u_fadeOutTime;
            }
            opacity *= a_baseOpacity * globalFadeIn;

            float distToLeft = position.x;
            float distToRight = u_canvasWidth - position.x;
            float distToTop = position.y;
            float distToBottom = u_canvasHeight - position.y;
            float distToEdge = min(min(distToLeft, distToRight), min(distToTop, distToBottom));

            if (distToEdge < u_edgeFadeZone) {
                opacity *= distToEdge / u_edgeFadeZone;
            }

            vec2 clipSpace = ((position / u_resolution) * 2.0 - 1.0) * vec2(1, -1);
            gl_Position = vec4(clipSpace, 0, 1);
            gl_PointSize = a_size;
            v_opacity = opacity;
        }
    """

    const val FRAGMENT_SHADER = """
        precision mediump float;

        uniform float u_useStar;
        varying float v_opacity;
        varying vec3 v_color;

        void main() {
            vec2 coord = gl_PointCoord - vec2(0.5);
            float alpha;

            if (u_useStar > 0.5) {
                float absX = abs(coord.x);
                float absY = abs(coord.y);

                float innerSize = 0.12;
                float armLength = 0.45;
                float armWidth = 0.08;

                float dist = 1.0;

                if (absX <= innerSize && absY <= innerSize) {
                    dist = max(absX, absY) - innerSize;
                } else if (absY <= armWidth && absX <= armLength) {
                    float normalizedX = (absX - innerSize) / (armLength - innerSize);
                    float taperFactor = 1.0 - normalizedX * 0.8;
                    float currentArmWidth = armWidth * taperFactor;
                    dist = absY - currentArmWidth;
                } else if (absX <= armWidth && absY <= armLength) {
                    float normalizedY = (absY - innerSize) / (armLength - innerSize);
                    float taperFactor = 1.0 - normalizedY * 0.8;
                    float currentArmWidth = armWidth * taperFactor;
                    dist = absX - currentArmWidth;
                }

                alpha = 1.0 - smoothstep(-0.01, 0.01, dist);
            } else {
                vec2 absCoord = abs(coord);

                float radius = 0.25;
                float squareSize = 0.5 - radius;

                vec2 cornerDist = max(absCoord - squareSize, 0.0);
                float dist = length(cornerDist);

                alpha = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
            }

            if (alpha <= 0.0) {
                discard;
            }

            gl_FragColor = vec4(v_color * v_opacity * alpha, v_opacity * alpha);
        }
    """
}
