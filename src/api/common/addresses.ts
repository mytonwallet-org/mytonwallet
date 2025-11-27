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

export async function tryUpdateKnownAddresses() {
  try {
    const data = await callBackendGet<{
      knownAddresses: Record<string, ApiKnownAddresses>;
      scamMarkers: string[];
      trustedSites: string[];
      trustedCollections: string[];
      tonNftSuperCollections: (ApiNftSuperCollection & { collections: string[] })[];
    }>('/known-addresses');

    knownAddresses = data.knownAddresses;
    scamMarkers = data.scamMarkers.map((x) => new RegExp(x, 'i'));
    trustedSites = new Set(data.trustedSites);
    trustedCollections = new Set(data.trustedCollections);
    tonNftSuperCollectionsByCollectionAddress = data.tonNftSuperCollections.reduce((acc, superCollection) => {
      const { collections, ...rest } = superCollection;

      collections.forEach((address) => {
        acc[address] = rest;
      });

      return acc;
    }, {} as Record<string, ApiNftSuperCollection>);
    nftSuperCollectionsDeferred.resolve();
  } catch (err) {
    logDebugError('tryUpdateKnownAddresses', err);
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
