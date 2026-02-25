import type {
  MethodArgs, Methods,
} from '../../methods/types';
import type {
  ApiInitArgs, OnApiUpdate,
} from '../../types';
import { recognizeDappMethod } from '../../types/methods';

import { createPostMessageInterface } from '../../../util/createPostMessageInterface';
import { getProtocolManager } from '../../dappProtocols';
import * as methods from '../../methods';
import init from '../../methods/init';

createPostMessageInterface((name: string, origin?: string, ...args: any[]) => {
  if (name === 'init') {
    return init(args[0] as OnApiUpdate, args[1] as ApiInitArgs);
  } else {
    const recognizedRequest = recognizeDappMethod(name);

    if (recognizedRequest.isDapp) {
      const adapter = getProtocolManager().getAdapter(recognizedRequest.protocolType);
      if (!adapter) {
        throw new Error('No dApp adapter found for request');
      }

      const method = adapter[recognizedRequest.fnName].bind(adapter);

      // @ts-ignore
      return method(...args);
    }

    const method = methods[name as keyof Methods];

    // @ts-ignore
    return method(...args as MethodArgs<keyof Methods>);
  }
});
