import {
  forceMeasure, getPhase, requestMutation,
} from '../../../lib/fasterdom/fasterdom';

export function measureStreamingTextDom<T>(measure: () => T) {
  if (getPhase() !== 'mutate') return measure();

  let result: T | undefined;
  let error: Error | undefined;
  forceMeasure(() => {
    try {
      result = measure();
    } catch (caughtError) {
      error = caughtError instanceof Error ? caughtError : new Error(String(caughtError));
    }
  });

  if (error) throw error;
  return result!;
}

export function mutateStreamingTextDom(mutate: NoneToVoidFunction) {
  if (getPhase() === 'mutate') {
    mutate();
  } else {
    requestMutation(mutate);
  }
}
