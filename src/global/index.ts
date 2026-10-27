import { typify } from '../lib/teact/teactn';

import type { ActionPayloads, GlobalState } from './types';

const typed = typify<GlobalState, ActionPayloads>();

export const getGlobal = typed.getGlobal;
export const setGlobal = typed.setGlobal;
export const getActions = typed.getActions;
export const getPromiseActions = typed.getPromiseActions;
export const addActionHandler = typed.addActionHandler;
export const withGlobal = typed.withGlobal;
