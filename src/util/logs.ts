import { DEBUG, DEBUG_API, IS_AIR_APP, IS_ANDROID } from '../config';
import { AssertionError } from './assert';

export interface Log {
  message: string;
  args: any[];
  time: number; // Passing data from the worker to the application as a date object is not supported
  level: 'debug' | 'debugError';
}

const MAX_LOG_LENGTH = 999;
const logs: Log[] = [];

export function errorReplacer(_: string, value: any) {
  if (value instanceof Error) {
    return {
      name: value.name,
      message: value.message,
      stack: value.stack,
      metadata: value instanceof AssertionError ? value.metadata : undefined,
    };
  }
  return value;
}

export function addLog(log: Omit<Log, 'time'>) {
  if (logs.length > MAX_LOG_LENGTH) {
    logs.shift();
  }

  logs.push({
    ...log,
    args: log.args.map((arg) => JSON.stringify(arg, errorReplacer)),
    time: Date.now(),
  });
}

export function getLogs() {
  return logs;
}

export function logDebugError(message: string, ...args: any[]) {
  addLog({ message, level: 'debugError', args });
  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.error(`[DEBUG][${message}]`, ...args);
  }
  if (IS_AIR_APP && IS_ANDROID) {
    (window as any).androidApp?.logDebugError(message, JSON.stringify(args, errorReplacer));
  }
}

export function logDebug(message: any, ...args: any[]) {
  addLog({ message, level: 'debug', args });
  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.log(`[DEBUG] ${message}`, ...args);
  }
}

export function logDebugApi(message: any, obj1: any, obj2?: any) {
  if (DEBUG_API) {
    // eslint-disable-next-line no-console
    console.debug(`[DEBUG] ${message}`);
    // eslint-disable-next-line no-console
    if (obj1) console.dir(obj1);
    // eslint-disable-next-line no-console
    if (obj2) console.dir(obj2);
  }
}

export function logSelfXssWarnings() {
  const selfXssWarnings: AnyLiteral = {
    en: 'WARNING! This console can be a way for bad people to take over your crypto wallet through something called '
      + 'a Self-XSS attack. So, don\'t put in or paste code you don\'t understand. Stay safe!',
    ru: 'ВНИМАНИЕ! Через эту консоль злоумышленники могут захватить ваш криптовалютный кошелёк с помощью так '
      + 'называемой атаки Self-XSS. Поэтому не вводите и не вставляйте код, который вы не понимаете. Берегите себя!',
    es: '¡ADVERTENCIA! Esta consola puede ser una forma en que las personas malintencionadas se apoderen de su '
      + 'billetera de criptomonedas mediante un ataque llamado Self-XSS. Por lo tanto, '
      + 'no introduzca ni pegue código que no comprenda. ¡Cuídese!',
    zh: '警告！这个控制台可能成为坏人通过所谓的Self-XSS攻击来接管你的加密货币钱包的方式。因此，请不要输入或粘贴您不理解的代码。请保护自己！',
  };

  const langCode = navigator.language.split('-')[0];
  const text = selfXssWarnings[langCode] || selfXssWarnings.en;

  // eslint-disable-next-line no-console
  console.log('%c%s', 'color: red; background: yellow; font-size: 18px;', text);
}
