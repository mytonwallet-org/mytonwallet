import resetScroll from './resetScroll';

describe('resetScroll', () => {
  it('keeps the existing scroll behavior by default', () => {
    const container = document.createElement('div');
    container.style.scrollBehavior = 'smooth';
    let scrollBehaviorAtRestore = '';

    Object.defineProperty(container, 'scrollTop', {
      configurable: true,
      set: () => {
        scrollBehaviorAtRestore = container.style.scrollBehavior;
      },
    });

    resetScroll(container, 120);

    expect(scrollBehaviorAtRestore).toBe('smooth');
  });

  it('can restore the position without inheriting smooth scrolling from the container', () => {
    const container = document.createElement('div');
    container.style.scrollBehavior = 'smooth';

    let appliedScrollTop = 0;
    let scrollBehaviorAtRestore = '';

    Object.defineProperty(container, 'scrollTop', {
      configurable: true,
      get: () => appliedScrollTop,
      set: (value: number) => {
        appliedScrollTop = value;
        scrollBehaviorAtRestore = container.style.scrollBehavior;
      },
    });

    resetScroll(container, 120, true);

    expect(appliedScrollTop).toBe(120);
    expect(scrollBehaviorAtRestore).toBe('auto');
    expect(container.style.scrollBehavior).toBe('smooth');
  });
});
