import { SECOND } from './dateFormat';
import { logDebug, logDebugError } from './logs';
import { debounce } from './schedulers';

import incomingTransactionSound from '../assets/incoming-transaction.mp3';

const DEBOUNCE_MS = SECOND;

const AudioContextConstructor = window.AudioContext || window.webkitAudioContext;
const audioContext = new AudioContextConstructor();
let audioBuffer: AudioBuffer | undefined;
let isSoundInitialized = audioContext.state === 'running';

// Workaround: this function is called once on the first user interaction.
// After that, it will be possible to play the notification without problems.
// https://developer.chrome.com/blog/autoplay?hl=ru#webaudio
export function initializeSounds() {
  if (isSoundInitialized) return;

  audioContext
    .resume()
    .then(() => {
      isSoundInitialized = true;
    })
    .catch((err: any) => {
      logDebugError('appSounds:initializeSounds', err);
    });
}

function loadSound() {
  fetch(incomingTransactionSound)
    .then((response) => response.arrayBuffer())
    .then((arrayBuffer) => audioContext.decodeAudioData(arrayBuffer))
    .then((decodedAudioBuffer) => {
      audioBuffer = decodedAudioBuffer;
    })
    .catch((err: any) => {
      logDebugError('appSounds:loadSound', err);
    });
}

void loadSound();

export const playIncomingTransactionSound = debounce(() => {
  if (!isSoundInitialized) {
    logDebug('appSounds:playIncomingTransactionSound', 'sound is not initialized');
    return;
  }

  if (!audioBuffer) {
    logDebug('playIncomingTransactionSound', 'audioBuffer is not loaded');
    return;
  }

  const source = audioContext.createBufferSource();
  source.buffer = audioBuffer;
  source.connect(audioContext.destination);
  source.start(0);
}, DEBOUNCE_MS, true, false);
