import { splitNftNumber } from './splitNftNumber';

describe('splitNftNumber', () => {
  it.each([
    ['Durov’s Cap #777', { name: 'Durov’s Cap', nftNumber: '#777' }],
    ['Collectible   #12', { name: 'Collectible', nftNumber: '#12' }],
    ['Item#5', { name: 'Item', nftNumber: '#5' }],
    ['Card №3', { name: 'Card', nftNumber: '№3' }],
    ['Ticket #12/100', { name: 'Ticket', nftNumber: '#12/100' }],
    ['  Padded #1  ', { name: 'Padded', nftNumber: '#1' }],
    ['Name #12a', { name: 'Name #12a' }],
    ['#5', { name: '#5' }],
    ['Plain Name', { name: 'Plain Name' }],
  ])('splits %p', (fullName, expected) => {
    expect(splitNftNumber(fullName)).toEqual(expected);
  });
});
