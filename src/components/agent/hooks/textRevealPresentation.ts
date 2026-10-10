export interface TextRevealPresentation {
  key: string;
  status: 'active' | 'settled' | 'error';
  shouldRevealFromStart: boolean;
}

export type TextRevealPresentations = Record<number, TextRevealPresentation>;

export function createTextRevealPresentation(
  generation: number,
  messageId: number,
  sequence: number,
): TextRevealPresentation {
  return {
    key: `${generation}:${messageId}:${sequence}`,
    status: 'active',
    shouldRevealFromStart: true,
  };
}

export function updateTextRevealPresentation(
  presentations: TextRevealPresentations,
  messageId: number,
  key: string,
  update: Partial<TextRevealPresentation>,
) {
  const presentation = presentations[messageId];
  if (!presentation || presentation.key !== key) return presentations;

  return {
    ...presentations,
    [messageId]: {
      ...presentation,
      ...update,
    },
  };
}
