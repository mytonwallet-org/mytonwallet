import { bundleStats } from 'rollup-plugin-bundle-stats';
import type { Plugin, Rolldown } from 'vite';

import { bundleManifest } from './bundleManifest';

type ReportPlugin = ReturnType<typeof bundleStats>;

const REPORT_DIR = 'bundle-stats';
const BASELINE_FILE = 'baseline.json';

/**
 * Bundle statistics for size tracking, written to `bundle-stats/` next to the bundle, together with
 * `bundle-manifest.json`.
 *
 * With `baselinePath`, which CI takes from the latest master build, the HTML report compares against it, and
 * the current stats are saved as `bundle-stats/baseline.json` for the PR comment. Without it, the current
 * stats become the baseline that master uploads.
 *
 * Workers are bundled separately, so their chunks are collected by `workerPlugins` and merged into the report.
 */
export function createBundleStatsPlugins(baselinePath?: string) {
  const workerBundles: Rolldown.OutputBundle[] = [];

  const plugins: Plugin[] = [
    bundleManifest(),
    withWorkerBundles(bundleStats({
      html: true,
      json: true,
      compare: Boolean(baselinePath),
      baseline: !baselinePath,
      baselineFilepath: baselinePath || BASELINE_FILE,
      outDir: REPORT_DIR,
    }), workerBundles),
    ...(baselinePath ? [withWorkerBundles(bundleStats({
      html: false,
      json: false,
      compare: false,
      baseline: true,
      baselineFilepath: BASELINE_FILE,
      outDir: REPORT_DIR,
      silent: true,
    }), workerBundles)] : []),
  ];

  const workerPlugins = (): Plugin[] => [{
    name: 'mtw:collect-worker-bundle',
    generateBundle(_, bundle) {
      workerBundles.push({ ...bundle });
    },
  }];

  return { plugins, workerPlugins };
}

function withWorkerBundles(plugin: ReportPlugin, workerBundles: Rolldown.OutputBundle[]): Plugin {
  return {
    name: `${plugin.name}:with-workers`,
    apply: 'build',
    async generateBundle(outputOptions, bundle, isWrite) {
      await plugin.generateBundle?.call(
        this,
        outputOptions as Parameters<NonNullable<ReportPlugin['generateBundle']>>[0],
        Object.assign({}, bundle, ...workerBundles),
        isWrite,
      );
    },
  };
}
