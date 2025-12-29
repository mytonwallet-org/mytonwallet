export interface ApiAddressInfo {
  /** The actual address. Is different from the input address if the input address is a domain name. */
  resolvedAddress: string;
  /** The name of the wallet behind the address */
  addressName?: string;
}
