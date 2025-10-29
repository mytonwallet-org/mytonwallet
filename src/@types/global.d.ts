declare const process: NodeJS.Process;

declare module '*.module.scss';

declare namespace React {
  interface HTMLAttributes {
    // Optimization for DOM nodes prepends and inserts
    teactFastList?: boolean;
    // `focusScroll.ts` uses this attribute to decide where to scroll the focused element to in Capacitor environments.
    // 'nearest' - no scroll unless the element is hidden; 'start' - the element will at the top; 'end' - at the bottom.
    'data-focus-scroll-position'?: ScrollLogicalPosition;
  }

  interface InputHTMLAttributes {
    // The internal implementation of the attribute is a boolean value
    // https://caniuse.com/mdn-html_global_attributes_autocorrect (see partial support notes)
    autoCorrect?: boolean;
  }

  // Teact feature
  // eslint-disable-next-line @typescript-eslint/no-wrapper-object-types, @typescript-eslint/no-empty-object-type
  interface CSSProperties extends String {}

  interface ClassAttributes<T> extends RefAttributes<T> {
    ref?: ((instance: T | undefined) => void) | React.RefObject<T | undefined> | undefined; // Teact ref
  }

  interface Attributes {
    // Optimization for DOM nodes reordering. Requires `teactFastList` for parent
    teactOrderKey?: number;
  }

  interface VideoHTMLAttributes {
    srcObject?: MediaStream;
  }

  interface MouseEvent {
    offsetX: number;
    offsetY: number;
  }

  interface KeyboardEvent {
    isComposing: boolean;
  }
}

type TeactJsx = any;

type AnyLiteral = Record<string, any>;
type AnyClass = new (...args: any[]) => any;
type AnyFunction = (...args: any[]) => any;
type AnyAsyncFunction = (...args: any[]) => Promise<any>;
type AnyToVoidFunction = (...args: any[]) => void;
type NoneToVoidFunction = () => void;
type MaybePromise<T> = Promise<T> | T;

type ValueOf<T> = T[keyof T];
type Entries<T> = [keyof T, ValueOf<T>][];
type EnsurePromise<T> = T extends Promise<any> ? T : Promise<T>;
type Override<T, U> = T extends any ? Omit<T, keyof U> & U : never;

type EmojiCategory = {
  id: string;
  name: string;
  emojis: string[];
};

type Emoji = {
  id: string;
  names: string[];
  native: string;
  image: string;
  skin?: number;
};

type EmojiWithSkins = Record<number, Emoji>;

type AllEmojis = Record<string, Emoji | EmojiWithSkins>;

// Declare supported for import formats as modules
declare module '*.webp';
declare module '*.png';
declare module '*.jpg';
declare module '*.avif';
declare module '*.svg';
declare module '*.tgs';
declare module '*.wasm';
declare module '*.mp3';
declare module '*.mp4';

declare module '*.txt' {
  const content: string;
  export default content;
}

declare module 'opus-recorder' {
  export interface IOpusRecorder extends Omit<MediaRecorder, 'start' | 'ondataavailable'> {
    // eslint-disable-next-line @typescript-eslint/no-misused-new
    new(options: AnyLiteral): IOpusRecorder;

    start(stream?: MediaStreamAudioSourceNode): void;

    sourceNode: MediaStreamAudioSourceNode;

    ondataavailable: (typedArray: Uint8Array) => void;
  }

  const recorder: IOpusRecorder;
  export default recorder;
}

interface TEncodedImage {
  result: Uint8ClampedArray;
  width: number;
  height: number;
}

interface IWebpWorker extends Worker {
  wasmReady?: boolean;
  requests: Map<string, (value: PromiseLike<TEncodedImage>) => void>;
}

interface Window {
  webkitAudioContext: typeof AudioContext;
}

interface Document {
  mozFullScreenElement: any;
  webkitFullscreenElement: any;
  mozCancelFullScreen?: () => Promise<void>;
  webkitCancelFullScreen?: () => Promise<void>;
  webkitExitFullscreen?: () => Promise<void>;
}

interface Element {
  dataset: DOMStringMap & {
    // See HTMLAttributes['data-focus-scroll-position']
    focusScrollPosition?: ScrollLogicalPosition;
  };
}

interface HTMLElement {
  mozRequestFullScreen?: () => Promise<void>;
  webkitEnterFullscreen?: () => Promise<void>;
  webkitRequestFullscreen?: () => Promise<void>;
}

interface Navigator {
  // PWA badging extensions https://w3c.github.io/badging/
  setAppBadge?(count: number): Promise<void>;
  // https://wicg.github.io/ua-client-hints/#dictdef-uadatavalues
  userAgentData?: {
    platform: string;
  };
}

// Fix to make Boolean() work as !!
// https://github.com/microsoft/TypeScript/issues/16655
type Falsy = false | 0 | '' | null | undefined;

interface BooleanConstructor {
  new<T>(value: T | Falsy): value is T;
  <T>(value: T | Falsy): value is T;
  readonly prototype: boolean;
}

interface Array<T> {
  filter<S extends T>(predicate: BooleanConstructor, thisArg?: any): Exclude<S, Falsy>[];
}
interface ReadonlyArray<T> {
  filter<S extends T>(predicate: BooleanConstructor, thisArg?: any): Exclude<S, Falsy>[];
}

// Missing type definitions for OPFS (Origin Private File System) API
// https://github.com/WICG/file-system-access/blob/main/AccessHandle.md#accesshandle-idl
interface FileSystemFileHandle extends FileSystemHandle {
  readonly kind: 'file';
  getFile(): Promise<File>;
  createSyncAccessHandle(): Promise<FileSystemSyncAccessHandle>;
}

interface FileSystemSyncAccessHandle {
  read: (buffer: BufferSource, options: FilesystemReadWriteOptions) => number;
  write: (buffer: BufferSource, options: FilesystemReadWriteOptions) => number;

  truncate: (size: number) => Promise<undefined>;
  getSize: () => Promise<number>;
  flush: () => Promise<undefined>;
  close: () => Promise<undefined>;
}

type FilesystemReadWriteOptions = {
  at: number;
};

interface Cordova {
  InAppBrowser: InAppBrowser;
}
