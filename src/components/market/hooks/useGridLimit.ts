import { useDeviceScreen } from '../../../hooks/useDeviceScreen';
import { useMediaQuery } from '../../../hooks/useMediaQuery';

// The grid shows two rows. The column counts mirror `grid-template-columns` of `.grid`
const GRID_LIMIT_PORTRAIT = 4 * 2;
const GRID_LIMIT_LANDSCAPE = 5 * 2;
const GRID_LIMIT_WIDE = 6 * 2;
// `md` breakpoint of `respond-above`
const WIDE_GRID_MEDIA_QUERY = '(min-width: 992px)';

export default function useGridLimit() {
  const { isPortrait } = useDeviceScreen();
  const isWideGrid = useMediaQuery(WIDE_GRID_MEDIA_QUERY);

  if (isPortrait) return GRID_LIMIT_PORTRAIT;

  return isWideGrid ? GRID_LIMIT_WIDE : GRID_LIMIT_LANDSCAPE;
}
