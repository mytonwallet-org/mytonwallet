export interface LovelyChartInstance {
  update: (newData: Record<string, unknown>) => void;
  destroy: () => void;
}

declare const LovelyChart: {
  create: (container: HTMLElement, config: Record<string, unknown>) => LovelyChartInstance;
};

export default LovelyChart;
