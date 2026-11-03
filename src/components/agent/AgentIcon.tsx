import React, { memo } from '../../lib/teact/teact';

export type AgentIconName = 'send' | 'like' | 'dislike' | 'microphone' | 'microphoneFilled';

// `Icons/20px/Microphone Icon`: its stand, then its capsule's outline
const MICROPHONE_STAND = 'M3.75 10.5V9.5C3.75 9.086 4.086 8.75 4.5 8.75C4.914 8.75 5.25 9.086 5.25 9.5V10.5C5.25 11.76 '
  + '5.751 12.968 6.642 13.858C7.532 14.749 8.74 15.25 10 15.25C11.26 15.25 12.468 14.749 13.358 13.858C14.249 '
  + '12.968 14.75 11.76 14.75 10.5V9.5C14.75 9.086 15.086 8.75 15.5 8.75C15.914 8.75 16.25 9.086 16.25 9.5V10.5C16.25 '
  + '12.158 15.591 13.747 14.419 14.919C13.425 15.913 12.131 16.536 10.75 16.703V17.5H12.5C12.914 17.5 13.25 17.836 '
  + '13.25 18.25C13.25 18.664 12.914 19 12.5 19H7.5C7.086 19 6.75 18.664 6.75 18.25C6.75 17.836 7.086 17.5 7.5 '
  + '17.5H9.25V16.703C7.869 16.536 6.575 15.913 5.581 14.919C4.409 13.747 3.75 12.158 3.75 10.5Z';
const MICROPHONE_CAPSULE = 'M13.75 10.25C13.75 12.321 12.071 14 10 14C7.929 14 6.25 12.321 6.25 10.25V5C6.25 2.929 '
  + '7.929 1.25 10 1.25C12.071 1.25 13.75 2.929 13.75 5V10.25Z';
const MICROPHONE_CAPSULE_HOLLOW = 'M12.25 5C12.25 3.757 11.243 2.75 10 2.75C8.757 2.75 7.75 3.757 7.75 5V10.25C7.75 '
  + `11.493 8.757 12.5 10 12.5C11.243 12.5 12.25 11.493 12.25 10.25V5Z${MICROPHONE_CAPSULE}`;

// The design's own glyphs for the icons the app's icon font draws differently, in their design boxes
const ICONS: Record<AgentIconName, { viewBox: string; paths: string[] }> = {
  // `Icons/24px/Arrow Down Icon`, turned to point up
  send: {
    viewBox: '0 0 22 22',
    paths: [
      'M11 19.525C11.658 19.525 12.192 18.992 12.192 18.333V6.544L15.657 10.009C16.123 10.475 16.877 10.475 '
      + '17.343 10.009C17.808 9.544 17.808 8.789 17.343 8.324L11.843 2.824C11.377 2.359 10.623 2.359 10.157 '
      + '2.824L4.657 8.324C4.192 8.789 4.192 9.544 4.657 10.009C5.123 10.475 5.877 10.475 6.343 10.009L9.808 '
      + '6.544V18.333C9.808 18.992 10.342 19.525 11 19.525Z',
    ],
  },
  // `Icons/Agent/up`
  like: {
    viewBox: '0 0 36 36',
    paths: [
      'M11.52 29.28H9.026C7.754 29.279 6.706 28.232 6.706 26.959V17.303C6.706 16.03 7.753 14.983 9.026 '
      + '14.983H11.52V29.28Z',
      'M20.972 6.075C21.763 6.075 22.847 6.656 22.847 8.007C22.847 9.467 22.407 11.692 21.526 14.682C21.482 '
      + '14.829 21.595 14.981 21.749 14.981H25.906C28.12 14.981 29.766 17.153 29.168 19.285L27.312 25.893C26.751 '
      + '27.889 24.918 29.28 22.844 29.28H12.96V14.622C13.184 14.481 13.386 14.301 13.553 14.086C15.182 11.991 '
      + '16.183 10.676 16.557 10.143C18.51 7.36 18.773 6.075 20.972 6.075Z',
    ],
  },
  // `Icons/Agent/down`
  dislike: {
    viewBox: '0 0 36 36',
    paths: [
      'M22.844 7.515C24.918 7.515 26.751 8.905 27.312 10.901L29.168 17.511C29.766 19.642 28.12 21.813 25.906 '
      + '21.813H21.749C21.595 21.813 21.482 21.965 21.526 22.112C22.407 25.103 22.847 27.329 22.847 28.789C22.847 '
      + '30.14 21.763 30.721 20.972 30.721C18.773 30.72 18.511 29.435 16.557 26.651C16.183 26.119 15.182 24.804 '
      + '13.553 22.708C13.386 22.493 13.184 22.314 12.96 22.172V7.515H22.844Z',
      'M11.52 7.515V21.813H9.026C7.753 21.813 6.706 20.766 6.706 19.493V9.835C6.706 8.562 7.754 7.515 9.026 '
      + '7.515H11.52Z',
    ],
  },
  microphone: {
    viewBox: '0 0 20 20',
    paths: [MICROPHONE_CAPSULE_HOLLOW, MICROPHONE_STAND],
  },
  // The same microphone with its capsule filled, for the recording circle
  microphoneFilled: {
    viewBox: '0 0 20 20',
    paths: [MICROPHONE_CAPSULE, MICROPHONE_STAND],
  },
};

interface OwnProps {
  name: AgentIconName;
  className?: string;
}

/** One of the design's glyphs, painted with the current color */
function AgentIcon({ name, className }: OwnProps) {
  const { viewBox, paths } = ICONS[name];

  return (
    <svg className={className} viewBox={viewBox} fill="currentColor" aria-hidden>
      {paths.map((d) => <path key={d} d={d} />)}
    </svg>
  );
}

export default memo(AgentIcon);
