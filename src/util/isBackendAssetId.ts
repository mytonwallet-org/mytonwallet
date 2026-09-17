/**
 * The backend spells an asset `<chain>:<address>`; a slug here is `<chain>-<address>` or a bare
 * name like `toncoin`. Such an id reaches a slug field when nothing resolved it.
 */
export function getIsBackendAssetId(value: string) {
  return value.includes(':');
}
