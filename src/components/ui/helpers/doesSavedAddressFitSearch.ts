import type { AddressBookItemData } from '../../../global/types';

export function doesSavedAddressFitSearch(
  { address, name, domain }: Pick<AddressBookItemData, 'address' | 'name' | 'domain'>,
  search: string,
): boolean {
  if (!search) return true;

  const searchQuery = search.toLowerCase();

  return (
    address.toLowerCase().includes(searchQuery)
    || name.toLowerCase().includes(searchQuery)
    || Boolean(domain?.toLowerCase().includes(searchQuery))
  );
}
