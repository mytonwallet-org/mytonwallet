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
const SILHOUETTE_CENTERED_VIEW_BOX = '-0.96 0.16 48 48';

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
        d="M20.971 42.925C20.376 42.906 19.746 42.728 19.35 42.261C17.779 40.408 18.135 35.863 15.483 33.168C14.855 32.53 13.777 31.576 12.981 31.184C11.386 30.398 5.607 29.155 5.625 26.77C5.644 24.235 11.653 25.013 13.174 24.936C13.73 24.908 14.695 24.716 15.234 24.557C16.643 24.14 18.617 22.62 19.56 21.493C21.586 19.071 23.141 14.439 23.98 11.388C24.384 9.922 24.787 7.842 25.574 6.562C25.981 5.901 26.555 5.398 27.367 5.397C28.439 5.395 29.175 5.923 29.481 6.959C29.939 8.508 29.242 11.868 29.077 13.584C28.798 16.505 28.66 19.779 29.27 22.664C30.998 30.827 40.444 29.585 40.455 33.139C40.463 35.872 33.504 34.857 31.905 34.906C31.491 34.919 30.422 35.202 30.005 35.341C28.521 35.837 27.232 36.554 26.15 37.707C24.996 38.936 22.568 42.977 20.971 42.925Z"
      />
    </svg>
  );
}

export default memo(AgentMark);
