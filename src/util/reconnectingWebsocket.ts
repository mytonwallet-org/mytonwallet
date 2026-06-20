import { DEFAULT_TIMEOUT } from '../config';
import { createCallbackManager } from './callbacks';
import { logDebug, logDebugError } from './logs';
import { setCancellableTimeout } from './schedulers';

export type InMessageCallback<T> = (message: T) => void;
export type ConnectCallback = NoneToVoidFunction;
/** isUnexpected is false when the socket is closed manually, i.e. by calling close() */
export type DisconnectCallback = (isUnexpected: boolean) => void;

const RECONNECT_BASE_DELAY = 500;
const RECONNECT_MAX_DELAY = 5000;

/**
 * Like WebSocket, but reconnects automatically when the socket disconnects
 */
export default class ReconnectingWebSocket<OutMessage, InMessage> {
  #url: string;

  #socket?: WebSocket;

  /** `true` between the `open` and the `close` events, i.e. when the socket can send and receive messages */
  #isConnected = false;

  #reconnectAttemptCount = 0;

  /** Cancels setTimeout of the WebSocket open timeout and the reconnect delay (they never happen simultaneously) */
  #cancelTimeout?: NoneToVoidFunction;

  #outMessageQueue: OutMessage[] = [];

  #inMessageListeners = createCallbackManager<InMessageCallback<InMessage>>();

  #connectListeners = createCallbackManager<ConnectCallback>();

  #disconnectListeners = createCallbackManager<DisconnectCallback>();

  constructor(url: string | URL) {
    this.#url = url.toString();
    this.#startSocket();
  }

  /**
   * Sends a message via the socket.
   * If the socket is disconnected, stashes the message until the socket is connected.
   */
  public send(message: OutMessage) {
    if (this.#socket && this.#isConnected) {
      this.#sendMessageNow(message);
    } else {
      this.#outMessageQueue.push(message);
    }
  }

  /**
   * Returns `true` is the socket is connected now. You may send messages regardless of the connection status.
   * The objects always initializes in the disconnected state.
   */
  public get isConnected() {
    return this.#isConnected;
  }

  /** Closes the current socket connection and creates a new one. Call it when you suspect the socket has hung. */
  public reconnect() {
    this.close();
    this.#startSocket();
  }

  /** Registers a callback firing when a message arrives from the socket */
  public onMessage(callback: InMessageCallback<InMessage>) {
    return this.#inMessageListeners.addCallback(callback);
  }

  /**
   * Registers a callback firing when the socket is connected initially or reconnected.
   * I.e. when isConnected switches from `false` to `true`.
   */
  public onConnect(callback: ConnectCallback) {
    return this.#connectListeners.addCallback(callback);
  }

  /**
   * Registers a callback firing when the socket is disconnected.
   * I.e. when isConnected switches from `true` to `false`.
   */
  public onDisconnect(callback: DisconnectCallback) {
    return this.#disconnectListeners.addCallback(callback);
  }

  /** Call it when you don't need the socket anymore. The callbacks won't fire after that. */
  public close() {
    this.#stopSocket();

    if (this.#isConnected) {
      this.#isConnected = false;
      this.#disconnectListeners.runCallbacks(false);
    }
  }

  #startSocket() {
    this.#stopSocket();

    this.#socket = new WebSocket(this.#url);
    this.#socket.binaryType = 'arraybuffer';

    this.#socket.onerror = () => logDebugError('WebSocket error event', this.#url);
    this.#socket.onopen = this.#handleSocketOpen;
    this.#socket.onclose = this.#handleSocketClose;
    this.#socket.onmessage = this.#handleSocketMessage;

    // If the socket doesn't open in several seconds, retry opening it
    this.#cancelTimeout = setCancellableTimeout(DEFAULT_TIMEOUT, () => this.#handleSocketClose('openTimeout'));
  }

  #stopSocket() {
    this.#cancelTimeout?.();

    if (!this.#socket) {
      return;
    }

    this.#socket.onerror = null; // eslint-disable-line no-null/no-null
    this.#socket.onopen = null; // eslint-disable-line no-null/no-null
    this.#socket.onclose = null; // eslint-disable-line no-null/no-null
    this.#socket.onmessage = null; // eslint-disable-line no-null/no-null
    this.#socket.close();

    this.#socket = undefined;
  }

  #sendMessageNow(message: OutMessage) {
    if (!this.#socket) throw new Error('No active socket');
    this.#socket.send(JSON.stringify(message));
  }

  #handleSocketOpen = () => {
    logDebug('WebSocket opened', this.#url);

    this.#cancelTimeout?.();
    this.#reconnectAttemptCount = 0;

    while (this.#outMessageQueue.length) {
      this.#sendMessageNow(this.#outMessageQueue.shift()!);
    }

    if (!this.#isConnected) {
      this.#isConnected = true;
      this.#connectListeners.runCallbacks();
    }
  };

  #handleSocketClose = (event: CloseEvent | 'openTimeout') => {
    if (event === 'openTimeout') {
      logDebugError('WebSocket open timeout');
    } else {
      logDebugError('WebSocket closed unexpectedly', event.code, event.reason, event.wasClean);
    }

    this.#stopSocket();

    this.#reconnectAttemptCount++;
    const reconnectDelay = Math.min(
      (RECONNECT_BASE_DELAY + (2000 * Math.random())) * this.#reconnectAttemptCount,
      RECONNECT_MAX_DELAY,
    );
    this.#cancelTimeout = setCancellableTimeout(reconnectDelay, () => this.#startSocket());

    if (this.#isConnected) {
      if (event === 'openTimeout') {
        throw new Error('Unexpected timeout event in an open socket');
      }

      this.#isConnected = false;
      this.#disconnectListeners.runCallbacks(true);
    }
  };

  #handleSocketMessage = ({ data }: MessageEvent<string | ArrayBuffer>) => {
    this.#inMessageListeners.runCallbacks(
      data instanceof ArrayBuffer
        ? data as InMessage
        : JSON.parse(data),
    );
  };
}
