const BASE_URL = 'https://dreamwalkers.io/ru/mytonwallet/';

export function buildAvanchangeUrl({
  address, give, take, type, amount,
}: {
  address: string;
  give: string;
  take: string;
  type: 'buy' | 'sell';
  amount?: string;
}): string {
  const params = new URLSearchParams({
    wallet: address,
    give,
    take,
    type,
  });

  if (amount) {
    params.set('give_amount', amount);
  }

  return `${BASE_URL}?${params.toString()}`;
}
