const PORT_DISCONNECTED_ERROR_MESSAGE = 'disconnected port';

export function isPortDisconnectedError(error: unknown) {
  let errorMessage = '';
  if (error instanceof Error) {
    errorMessage = error.message;
  } else if (typeof error === 'string') {
    errorMessage = error;
  } else if (typeof error === 'number' || typeof error === 'boolean') {
    errorMessage = String(error);
  }

  return errorMessage.includes(PORT_DISCONNECTED_ERROR_MESSAGE);
}
