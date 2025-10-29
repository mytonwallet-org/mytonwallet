import type { SavedAddress } from '../../../global/types';

export function doesSavedAddressFitSearch(
  savedAddress: Pick<SavedAddress, 'address' | 'name'>,
  search: string,
): boolean {
  if (!search) return true;

  const searchQuery = search.toLowerCase();
  const { address, name } = savedAddress;

  return (
    address.toLowerCase().startsWith(searchQuery)
    || address.toLowerCase().endsWith(searchQuery)
    || name.toLowerCase().split(/\s+/).some((part) => part.startsWith(searchQuery))
  );
}
