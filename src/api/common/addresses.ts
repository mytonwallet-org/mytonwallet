import type { ApiKnownAddresses, ApiKnownAddressInfo, ApiNftSuperCollection } from '../types';

import { RE_LINK_TEMPLATE, RE_TG_BOT_MENTION } from '../../config';
import { cleanText } from '../../lib/confusables';
import Deferred from '../../util/Deferred';
import { logDebugError } from '../../util/logs';
import { callBackendGet } from './backend';

let knownAddresses: ApiKnownAddresses = {};
let scamMarkers: RegExp[] = [];
let trustedSites = new Set<string>();
let trustedCollections = new Set<string>();
let tonNftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection> = {};
const nftSuperCollectionsDeferred = new Deferred();

export async function tryUpdateKnownAddresses(
  lastResponse?: { text?: string; isStopped?: boolean; isLoading?: boolean },
  shouldSkipUnchanged = false,
) {
  if (lastResponse?.isLoading) return;
  if (lastResponse) lastResponse.isLoading = true;
  try {
    const text = lastResponse
      ? await callBackendGet('/known-addresses', undefined, undefined, undefined, { shouldReturnText: true })
      : undefined;
    if (lastResponse?.isStopped) {
      nftSuperCollectionsDeferred.resolve();
      return;
    }
    if (shouldSkipUnchanged && lastResponse && text === lastResponse.text) return;

    const data: {
      knownAddresses: Record<string, ApiKnownAddresses>;
      scamMarkers: string[];
      trustedSites: string[];
      trustedCollections: string[];
      tonNftSuperCollections: (ApiNftSuperCollection & { collections: string[] })[];
    } = text === undefined ? await callBackendGet('/known-addresses') : JSON.parse(text);

    const newScamMarkers = data.scamMarkers.map((x) => new RegExp(x, 'i'));
    const newTrustedSites = new Set(data.trustedSites);
    const newTrustedCollections = new Set(data.trustedCollections);
    const newTonNftSuperCollectionsByCollectionAddress = data.tonNftSuperCollections.reduce((acc, superCollection) => {
      const { collections, ...rest } = superCollection;

      collections.forEach((address) => {
        acc[address] = rest;
      });

      return acc;
    }, {} as Record<string, ApiNftSuperCollection>);

    knownAddresses = data.knownAddresses;
    scamMarkers = newScamMarkers;
    trustedSites = newTrustedSites;
    trustedCollections = newTrustedCollections;
    tonNftSuperCollectionsByCollectionAddress = newTonNftSuperCollectionsByCollectionAddress;
    nftSuperCollectionsDeferred.resolve();
    if (lastResponse) lastResponse.text = text;
  } catch (err) {
    logDebugError('tryUpdateKnownAddresses', err);
    nftSuperCollectionsDeferred.resolve();
  } finally {
    if (lastResponse) lastResponse.isLoading = false;
  }
}

export function getKnownAddresses() {
  return knownAddresses;
}

export async function getNftSuperCollectionsByCollectionAddress() {
  await nftSuperCollectionsDeferred.promise;

  return tonNftSuperCollectionsByCollectionAddress;
}

export function getScamMarkers() {
  return scamMarkers;
}

export function getKnownAddressInfo(address: string): ApiKnownAddressInfo | undefined {
  return knownAddresses[address];
}

export function checkIsTrustedSite(domain: string) {
  return trustedSites.has(domain.toLowerCase());
}

export function checkIsTrustedCollection(address: string) {
  return trustedCollections.has(address);
}

/** The set is empty until `/known-addresses` responds, and stays empty when the request fails */
export function getHasTrustedCollections() {
  return trustedCollections.size > 0;
}

export function checkHasScamLink(text: string) {
  const matches = cleanText(text).matchAll(RE_LINK_TEMPLATE);

  for (const match of matches) {
    const host = match.groups?.host;
    if (host && !checkIsTrustedSite(host)) {
      return true;
    }
  }

  return false;
}

export function checkHasTelegramBotMention(text: string) {
  return RE_TG_BOT_MENTION.test(cleanText(text));
}
