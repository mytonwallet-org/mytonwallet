import { useMemo, useState } from '../lib/teact/teact';

import type { ApiChain } from '../api/types';
import type { DropdownItem } from '../components/ui/Dropdown';
import type { ExplorerConfig } from '../util/chain';

import { getAvailableExplorers } from '../util/chain';
import { convertExplorerUrl, getExplorerByUrl } from '../util/url';
import useEffectWithPrevDeps from './useEffectWithPrevDeps';
import useLastCallback from './useLastCallback';

interface UseExplorerUrlParams {
  url?: string;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
  isTestnet?: boolean;
  onExplorerChange?: (chain: ApiChain, explorerId: string) => void;
}

interface ExplorerInfo {
  chain: ApiChain;
  explorerId: string;
}

interface UseExplorerUrlResult {
  currentUrl: string | undefined;
  explorers: ExplorerConfig[] | undefined;
  explorerInfo: ExplorerInfo | undefined;
  currentExplorerId: string | undefined;
  dropdownItems: DropdownItem<string>[];
  handleExplorerChange: (explorerId: string) => void;
}

export default function useExplorerUrl({
  url,
  selectedExplorerIds,
  isTestnet,
  onExplorerChange,
}: UseExplorerUrlParams): UseExplorerUrlResult {
  const explorerInfo = useMemo(() => url ? getExplorerByUrl(url) : undefined, [url]);
  const explorers = useMemo(
    () => explorerInfo && getAvailableExplorers(explorerInfo.chain),
    [explorerInfo],
  );

  const [currentUrl, setCurrentUrl] = useState<string | undefined>(url);
  const [currentExplorerId, setCurrentExplorerId] = useState<string | undefined>(explorerInfo?.explorerId);

  useEffectWithPrevDeps(([prevUrl]) => {
    if (!url) {
      setCurrentUrl(undefined);
      setCurrentExplorerId(undefined);
      return;
    }

    if (url === prevUrl) return;

    // If it's not an explorer URL, just use it as-is
    if (!explorerInfo) {
      setCurrentUrl(url);
      setCurrentExplorerId(undefined);
      return;
    }

    if (!explorers) return;

    // For explorer URLs, apply conversion logic if user has a saved preference
    const savedExplorerId = selectedExplorerIds?.[explorerInfo.chain];
    const nextUrl = savedExplorerId && savedExplorerId !== explorerInfo.explorerId
      ? convertExplorerUrl(url, savedExplorerId) || url
      : url;

    setCurrentExplorerId(savedExplorerId || explorerInfo.explorerId);
    setCurrentUrl(nextUrl);
  }, [url, explorerInfo, selectedExplorerIds, explorers, isTestnet]);

  const dropdownItems = useMemo<DropdownItem<string>[]>(() => {
    if (!explorers || explorers.length <= 1) return [];

    return explorers.map((explorer: ExplorerConfig) => ({
      value: explorer.id,
      name: explorer.name,
    }));
  }, [explorers]);

  const handleExplorerChange = useLastCallback((explorerId: string) => {
    if (!currentUrl || !explorerInfo || !explorers || !currentExplorerId) return;

    // Fallback to current URL if conversion fails
    const newUrl = convertExplorerUrl(currentUrl, explorerId) ?? currentUrl;

    setCurrentExplorerId(explorerId);
    onExplorerChange?.(explorerInfo.chain, explorerId);
    setCurrentUrl(newUrl);
  });

  return {
    currentUrl,
    explorers,
    explorerInfo,
    currentExplorerId,
    dropdownItems,
    handleExplorerChange,
  };
}
