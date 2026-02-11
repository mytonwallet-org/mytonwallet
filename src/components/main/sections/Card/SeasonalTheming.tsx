import React, { type ElementRef, memo } from '../../../../lib/teact/teact';

import type { ApiBackendConfig } from '../../../../api/types/backend';
import type { DropdownItem } from '../../../ui/Dropdown';

import buildClassName from '../../../../util/buildClassName';

import NewYearGarland from '../../../mintCard/NewYearGarland';
import ValentineDecoration from '../../../mintCard/ValentineDecoration';
import WithContextMenu from '../../../ui/WithContextMenu';

import styles from './Card.module.scss';

interface OwnProps {
  animationLevel: number;
  seasonalTheme?: ApiBackendConfig['seasonalTheme'];
  isSeasonalThemingDisabled?: boolean;
  seasonalContextMenuItems: DropdownItem<'disable'>[];
  onDisableSeasonalTheming: NoneToVoidFunction;
}

function SeasonalTheming({
  animationLevel,
  seasonalTheme,
  isSeasonalThemingDisabled,
  seasonalContextMenuItems,
  onDisableSeasonalTheming,
}: OwnProps) {
  if (isSeasonalThemingDisabled || !seasonalTheme) {
    return undefined;
  }

  if (seasonalTheme === 'newYear') {
    return (
      <WithContextMenu
        layout={{
          isCenteredHorizontally: false,
          doNotCoverTrigger: false,
        }}
        items={seasonalContextMenuItems}
        onItemClick={onDisableSeasonalTheming}
      >
        {(menuProps) => (
          <div
            ref={menuProps.ref as ElementRef<HTMLDivElement>}
            onMouseDown={menuProps.onMouseDown}
            onContextMenu={menuProps.onContextMenu}
            className={buildClassName(styles.seasonalGarland, menuProps.className)}
          >
            <NewYearGarland animationLevel={animationLevel} />
          </div>
        )}
      </WithContextMenu>
    );
  }

  if (seasonalTheme === 'valentine') {
    return (
      <WithContextMenu
        layout={{
          isCenteredHorizontally: false,
          doNotCoverTrigger: false,
        }}
        items={seasonalContextMenuItems}
        onItemClick={onDisableSeasonalTheming}
      >
        {(menuProps) => (
          <div
            ref={menuProps.ref as ElementRef<HTMLDivElement>}
            onMouseDown={menuProps.onMouseDown}
            onContextMenu={menuProps.onContextMenu}
            className={buildClassName(styles.seasonalValentine, menuProps.className)}
          >
            <ValentineDecoration animationLevel={animationLevel} />
          </div>
        )}
      </WithContextMenu>
    );
  }

  return undefined;
}

export default memo(SeasonalTheming);
