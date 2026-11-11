import 'dotenv/config';

import { Buffer } from 'buffer/';
import { webcrypto as crypto } from 'node:crypto';
import { CompressionStream, DecompressionStream, ReadableStream } from 'node:stream/web';
import { TextDecoder, TextEncoder } from 'node:util';

jest.mock('../src/lib/tlottie/TLottie');

Object.assign(global, {
  Buffer,
});

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: jest.fn()
    .mockImplementation((query) => ({
      matches: false,
      media: query,
      // eslint-disable-next-line no-null/no-null
      onchange: null,
      addListener: jest.fn(), // Deprecated
      removeListener: jest.fn(), // Deprecated
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      dispatchEvent: jest.fn(),
    })),
});

Object.defineProperty(global.Element.prototype, 'innerText', {
  get(this: Element) {
    const el = this.cloneNode(true) as typeof this; // can skip if mutability isn't a concern
    el.querySelectorAll('script,style')
      .forEach((s) => s.remove());
    return el.textContent;
  },
  configurable: true, // make it so that it doesn't blow chunks on re-running tests with things like --watch
});

Object.defineProperty(global, 'IntersectionObserver', {
  writable: true,
  configurable: true,
  value: class {
    observe() {
    }

    unobserve() {
    }

    disconnect() {
    }
  },
});

Object.defineProperty(global, 'ResizeObserver', {
  writable: true,
  configurable: true,
  value: class {
    observe() {
    }

    unobserve() {
    }

    disconnect() {
    }
  },
});

Object.defineProperty(global, 'indexedDB', {
  writable: true,
  configurable: true,
  value: {
    open() {
      return {};
    },
  },
});

// These APIs are available in the Node.js global scope, but JSDOM removes or breaks them, so we need to retrieve them
Object.assign(global, {
  TextEncoder,
  TextDecoder,
  CompressionStream,
  DecompressionStream,
  ReadableStream,
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  Uint8Array: Object.getPrototypeOf(Object.getPrototypeOf(require('node:buffer').Buffer.from(''))).constructor, // The JSDOM's implementation isn't compatible with 'node:crypto'
});
Object.defineProperty(global, 'crypto', {
  value: crypto,
  configurable: true,
});

// Importing dynamically, because the file execution fails without the above mocks
void import('./initGlobal');
