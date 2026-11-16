import { getNftSuperCollectionsByCollectionAddress, tryUpdateKnownAddresses } from './addresses';
import { callBackendGet } from './backend';

jest.mock('./backend', () => ({ callBackendGet: jest.fn() }));
jest.mock('../../util/logs', () => ({ logDebugError: jest.fn() }));

it('requires a successful registry, recovers after failure and retains the last valid registry', async () => {
  // This mock covers both the JSON and shouldReturnText overloads of the same function.
  const fetch = jest.mocked(callBackendGet) as unknown as jest.Mock<Promise<AnyLiteral | string>>;
  fetch.mockRejectedValueOnce(new Error('Offline'));
  await tryUpdateKnownAddresses();
  await expect(getNftSuperCollectionsByCollectionAddress(true)).rejects.toThrow('classification unavailable');
  // Optional callers retain their previous behavior; inventory completion opts in to the strict read.
  await expect(getNftSuperCollectionsByCollectionAddress()).resolves.toEqual({});

  const response = {
    knownAddresses: {}, scamMarkers: [], trustedSites: [], trustedCollections: [], tonNftSuperCollections: [],
  };
  fetch.mockResolvedValueOnce(JSON.stringify(response));
  await tryUpdateKnownAddresses({ isStopped: true });
  await expect(getNftSuperCollectionsByCollectionAddress(true)).rejects.toThrow('classification unavailable');

  // An authoritative empty registry is distinct from a failed request.
  fetch.mockResolvedValueOnce(response);
  await tryUpdateKnownAddresses();
  const registry = await getNftSuperCollectionsByCollectionAddress(true);
  expect(registry).toEqual({});
  fetch.mockRejectedValueOnce(new Error('Offline again'));
  await tryUpdateKnownAddresses();
  expect(await getNftSuperCollectionsByCollectionAddress(true)).toBe(registry);

  const lastResponse = { text: JSON.stringify(response) };
  fetch.mockResolvedValueOnce(lastResponse.text);
  await tryUpdateKnownAddresses(lastResponse, true);
  expect(await getNftSuperCollectionsByCollectionAddress(true)).toBe(registry);
});
