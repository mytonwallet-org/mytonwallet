type HandlerName = 'onEnter' | 'onBackspace' | 'onDelete' | 'onEsc' | 'onUp' | 'onDown' | 'onLeft' | 'onRight'
  | 'onTab' | 'onSpace';
type EventHandler = (e: KeyboardEvent) => boolean | void | Promise<void>;
type HandlerWithOptions = {
  handler: (e: KeyboardEvent) => void;
  shouldPreventDefault?: boolean;
  noStopPropagation?: boolean;
};

type Handler = EventHandler | HandlerWithOptions;

type CaptureOptions = Partial<Record<HandlerName, Handler>>;

const keyToHandlerName: Record<string, HandlerName> = {
  Enter: 'onEnter',
  Backspace: 'onBackspace',
  Delete: 'onDelete',
  Esc: 'onEsc',
  Escape: 'onEsc',
  ArrowUp: 'onUp',
  ArrowDown: 'onDown',
  ArrowLeft: 'onLeft',
  ArrowRight: 'onRight',
  Tab: 'onTab',
  ' ': 'onSpace',
};

const handlers: Record<HandlerName, Handler[]> = {
  onEnter: [],
  onDelete: [],
  onBackspace: [],
  onEsc: [],
  onUp: [],
  onDown: [],
  onLeft: [],
  onRight: [],
  onTab: [],
  onSpace: [],
};

export default function captureKeyboardListeners(options: CaptureOptions) {
  if (!hasActiveHandlers()) {
    document.addEventListener('keydown', handleKeyDown, true);
  }

  (Object.keys(options) as Array<HandlerName>).forEach((handlerName) => {
    const option = options[handlerName];
    if (!option) {
      return;
    }

    const currentEventHandlers = handlers[handlerName];
    if (currentEventHandlers) {
      currentEventHandlers.push(option);
    }
  });

  return () => {
    releaseKeyboardListener(options);
  };
}

function hasActiveHandlers() {
  return Object.values(handlers).some((keyHandlers) => Boolean(keyHandlers.length));
}

function handleKeyDown(e: KeyboardEvent) {
  const handlerName = keyToHandlerName[e.key];
  if (!handlerName) {
    return;
  }

  const { length } = handlers[handlerName];
  if (!length) {
    return;
  }

  const handlerOrOptions = handlers[handlerName][length - 1];

  if (typeof handlerOrOptions === 'function') {
    void handlerOrOptions(e);

    e.stopPropagation();
  } else {
    const { handler, noStopPropagation, shouldPreventDefault } = handlerOrOptions;
    if (!noStopPropagation) {
      e.stopPropagation();
    }
    if (shouldPreventDefault) {
      e.preventDefault();
    }
    handler(e);
  }
}

function releaseKeyboardListener(options: CaptureOptions) {
  (Object.keys(options) as Array<HandlerName>).forEach((handlerName) => {
    const option = options[handlerName];
    const currentEventHandlers = handlers[handlerName];
    if (currentEventHandlers) {
      const index = currentEventHandlers.findIndex((cb) => {
        if (typeof cb === 'function') {
          return cb === option;
        } else {
          return option && 'handler' in option && cb.handler === option.handler;
        }
      });

      if (index !== -1) {
        currentEventHandlers.splice(index, 1);
      }
    }
  });

  if (!hasActiveHandlers()) {
    document.removeEventListener('keydown', handleKeyDown, false);
  }
}
