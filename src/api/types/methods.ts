import type { ExtensionMethods } from '../extensionMethods/types';
import type { Methods } from '../methods/types';
import {
  DAPP_PROTOCOL_TYPES,
  type DappProtocolAdapter,
  type DappProtocolType,
} from '../dappProtocols/types';

type PrefixedDappAdapterMethods = {
  [P in keyof DappProtocolAdapter as `${DappProtocolType}_${P}`]:
  DappProtocolAdapter[P] extends (...args: any) => any ? DappProtocolAdapter[P] : never
};

type DappAdapterMethods<T extends `${DappProtocolType}` = any> = {
  [P in keyof DappProtocolAdapter<T>]-?:
  DappProtocolAdapter<T>[P] extends ((...args: any) => any) | undefined ? DappProtocolAdapter<T>[P] : never
};

export type AllMethods = Methods & ExtensionMethods & PrefixedDappAdapterMethods;

type GeneralMethodArgs<N extends keyof AllMethods> = Parameters<
  AllMethods[N] extends (...args: any) => any ? AllMethods[N] : never
>;
type GeneralMethodResponse<N extends keyof AllMethods> = Awaited<
  ReturnType<AllMethods[N] extends (...args: any) => any ? AllMethods[N] : never>
>;

type ResolveMaybeDappMethod<
  Prefix extends string,
  MethodName extends string,
  Fallback,
  Mode extends 'args' | 'response',
> = Prefix extends `${DappProtocolType}`
  ? MethodName extends keyof DappAdapterMethods<Prefix>
    ? DappAdapterMethods<Prefix>[MethodName] extends infer A extends ((...args: any) => any)
      ? Mode extends 'args' ? Parameters<A> : Awaited<ReturnType<A>>
      : Fallback
    : Fallback
  : Fallback;

export type MethodArgsWithMaybePrefix<T extends keyof AllMethods> = T extends `${infer P}_${infer M}`
  ? ResolveMaybeDappMethod<P, M, GeneralMethodArgs<T>, 'args'>
  : GeneralMethodArgs<T>;

export type MethodResponseWithMaybePrefix<T extends keyof AllMethods> = T extends `${infer P}_${infer M}`
  ? ResolveMaybeDappMethod<P, M, GeneralMethodResponse<T>, 'response'>
  : GeneralMethodResponse<T>;

type DiscriminatedMethods =
  | {
    isDapp: true;
    fnName: keyof DappAdapterMethods;
    protocolType: DappProtocolType;
  } | {
    isDapp: false;
    fnName: (keyof Methods & ExtensionMethods);
  };

export function recognizeDappMethod(fnName: string): DiscriminatedMethods {
  const splitted = fnName.split('_');
  if (splitted.length > 1 && DAPP_PROTOCOL_TYPES.includes(splitted[0] as any)) {
    return {
      isDapp: true,
      fnName: splitted[1] as keyof DappAdapterMethods,
      protocolType: splitted[0] as DappProtocolType,
    };
  }
  return {
    isDapp: false,
    fnName: fnName as (keyof Methods & ExtensionMethods),
  };
}
