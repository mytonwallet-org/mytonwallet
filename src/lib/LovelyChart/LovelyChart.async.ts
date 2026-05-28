type LovelyChartModule = typeof import('./lovelyChartWithStyles').default;

let promise: Promise<LovelyChartModule> | undefined;

export function ensureLovelyChart() {
  if (!promise) {
    promise = import('./lovelyChartWithStyles').then((module) => module.default);
  }

  return promise;
}
