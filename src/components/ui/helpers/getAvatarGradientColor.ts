const gradients: [string, string][] = [
  ['#72D5FD', '#2A9EF1'],
  ['#FF885E', '#FF516A'],
  ['#A0DE7E', '#54CB68'],
  ['#FFCD6A', '#FFA85C'],
  ['#82B1FF', '#665FFF'],
  ['#53EDD6', '#28C9B7'],
  ['#E0A2F3', '#D669ED'],
];

export function getAvatarGradientColors(accountId: string): [string, string] {
  const hash = accountId.split('').reduce((acc, char) => {
    return char.charCodeAt(0) + ((acc << 5) - acc);
  }, 0);

  return gradients[Math.abs(hash) % gradients.length];
}
