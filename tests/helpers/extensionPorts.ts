function event<T extends AnyFunction>() {
  const listeners = new Set<T>();
  return {
    addListener: (listener: T) => listeners.add(listener),
    removeListener: (listener: T) => listeners.delete(listener),
    emit: (...args: Parameters<T>) => listeners.forEach((listener) => listener(...args)),
  };
}

type TestPort = {
  name: string;
  onMessage: ReturnType<typeof event<(data: string) => void>>;
  onDisconnect: ReturnType<typeof event<NoneToVoidFunction>>;
  postMessage: (data: string) => void;
};

export function installTestExtensionPorts() {
  const previousChrome = global.chrome;
  const onConnect = event<(port: chrome.runtime.Port) => void>();
  const pairs: { client: TestPort; server: TestPort; disconnect: (shouldReconnect?: boolean) => void }[] = [];

  function connect({ name }: { name: string }) {
    const client = { name, onMessage: event<(data: string) => void>(), onDisconnect: event<NoneToVoidFunction>() };
    const server = {
      ...client,
      sender: { url: 'chrome-extension://fixture/index.html' },
      onMessage: event<(data: string) => void>(),
      onDisconnect: event<NoneToVoidFunction>(),
    };
    let isClosed = false;
    function deliver(target: typeof client, data: string) {
      if (isClosed) throw new Error('Attempting to use a disconnected port object');
      queueMicrotask(() => target.onMessage.emit(data));
    }
    const clientPort = { ...client, postMessage: (data: string) => deliver(server, data) };
    const serverPort = { ...server, postMessage: (data: string) => deliver(client, data) };
    const pair = {
      client: clientPort,
      server: serverPort,
      disconnect(shouldReconnect = false) {
        isClosed = true;
        server.onDisconnect.emit();
        if (shouldReconnect) client.onDisconnect.emit();
      },
    };
    pairs.push(pair);
    onConnect.emit(serverPort as unknown as chrome.runtime.Port);
    return pair;
  }

  global.chrome = { runtime: {
    onConnect,
    connect: (options: { name: string }) => connect(options).client,
  } } as unknown as typeof chrome;

  return { pairs, restore: () => {
    pairs.forEach((pair) => pair.disconnect());
    global.chrome = previousChrome;
  } };
}
