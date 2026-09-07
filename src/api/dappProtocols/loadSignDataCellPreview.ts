import type { ApiParsedSignDataCellPreview } from './signDataCellPreview';

type SignDataCellPreviewModule = Pick<
  typeof import('./signDataCellPreview'),
  'buildSignDataCellPreview'
>;

export type SignDataCellPreviewModuleLoader = () => Promise<SignDataCellPreviewModule>;

const loadPreviewModule: SignDataCellPreviewModuleLoader = () => import(
  /* webpackChunkName: "signDataCellPreview" */ './signDataCellPreview',
);

export async function loadSignDataCellPreview(
  cellBase64: string,
  schema: string | undefined,
  loadModule: SignDataCellPreviewModuleLoader = loadPreviewModule,
): Promise<ApiParsedSignDataCellPreview | undefined> {
  try {
    const { buildSignDataCellPreview } = await loadModule();
    return buildSignDataCellPreview(cellBase64, schema);
  } catch {
    // Preview parsing is best-effort. The original request must still reach the confirmation UI,
    // which displays the raw schema/cell together with the unclear-binary warning.
    return undefined;
  }
}
