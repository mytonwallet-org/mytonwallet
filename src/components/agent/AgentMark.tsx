import React, { memo } from '../../lib/teact/teact';

import useUniqueId from '../../hooks/useUniqueId';

interface OwnProps {
  className?: string;
  /** Paints the mark with the Agent gradient instead of the current color */
  withGradient?: boolean;
  /** Lets the gradient show through at 30–60 %, as the empty chat's mark does */
  isGradientSoft?: boolean;
}

// The 48 × 48 design box of the mark, shifted so that the silhouette, rather than the box, sits in the middle
const SILHOUETTE_CENTERED_VIEW_BOX = '-1.32 0.3 48 48';

/** The Agent's spinning top mark */
function AgentMark({ className, withGradient, isGradientSoft }: OwnProps) {
  const gradientId = useUniqueId('agent-mark-');

  return (
    <svg className={className} viewBox={SILHOUETTE_CENTERED_VIEW_BOX} aria-hidden>
      {withGradient && (
        <defs>
          {/* The coating of the spinning top on mobile, along its body */}
          <linearGradient id={gradientId} gradientUnits="userSpaceOnUse" x1="9.637" y1="1.942" x2="47.963" y2="12.803">
            <stop offset="0" stop-color="#0088FF" stop-opacity={isGradientSoft ? '0.3' : '1'} />
            <stop offset="0.476" stop-color="#00BEFF" stop-opacity={isGradientSoft ? '0.6' : '1'} />
            <stop offset="1" stop-color="#B656FF" stop-opacity={isGradientSoft ? '0.3' : '1'} />
          </linearGradient>
        </defs>
      )}
      <path
        fill={withGradient ? `url(#${gradientId})` : 'currentColor'}
        d="M27.927 5.83C28.426 5.936 28.849 6.138 29.179 6.45C29.51 6.761 29.721 7.156 29.844 7.599C30.081 8.463 29.994 9.568 29.765 10.807C29.067 14.572 28.614 17.802 28.639 20.568C28.663 23.329 29.165 25.593 30.341 27.455L30.696 27.966C32.572 30.425 35.839 31.494 39.099 32.332L39.542 32.474C39.963 32.634 40.315 32.854 40.57 33.123C40.916 33.489 41.103 33.978 40.951 34.488C40.802 34.999 40.44 35.349 39.963 35.528C39.505 35.7 38.952 35.715 38.368 35.619L38.364 35.618C33.17 34.734 29.828 35.004 27.443 36.262L27.441 36.263C26.392 36.812 25.476 37.978 24.535 39.262C24.078 39.885 23.616 40.533 23.151 41.094C22.688 41.654 22.189 42.165 21.644 42.503L21.642 42.504C21.168 42.794 20.613 42.903 20.072 42.788C19.53 42.673 19.066 42.347 18.751 41.89L18.75 41.888C18.389 41.357 18.143 40.688 17.947 39.988C17.751 39.286 17.592 38.506 17.428 37.751C17.091 36.196 16.727 34.758 15.992 33.83C14.324 31.71 11.38 30.102 6.275 28.797C5.702 28.647 5.2 28.409 4.851 28.065C4.489 27.707 4.299 27.24 4.372 26.713L4.412 26.522C4.535 26.095 4.868 25.791 5.275 25.621C5.732 25.431 6.311 25.391 6.94 25.496C10.479 26.094 14.134 26.454 16.924 24.603C18.757 23.38 20.136 21.516 21.281 19.004C22.429 16.487 23.329 13.353 24.223 9.629C24.517 8.404 24.889 7.359 25.457 6.667C25.749 6.312 26.102 6.037 26.532 5.887C26.96 5.737 27.428 5.724 27.927 5.83Z"
      />
    </svg>
  );
}

export default memo(AgentMark);
