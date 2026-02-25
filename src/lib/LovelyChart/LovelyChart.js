var LovelyChart = function(exports) {
  "use strict";
  const DPR = window.devicePixelRatio || 1;
  const DEFAULT_RANGE = { begin: 0.8, end: 1 };
  const TRANSITION_DEFAULT_DURATION = 400;
  const LONG_PRESS_TIMEOUT = 500;
  const GUTTER = 10;
  const PLOT_HEIGHT = 320;
  const PLOT_TOP_PADDING = 15;
  const PLOT_LINE_WIDTH = 2;
  const PLOT_PIE_RADIUS_FACTOR = 0.9 / 2;
  const PLOT_PIE_SHIFT = 10;
  const PLOT_BARS_WIDTH_SHIFT = 0.5;
  const PIE_MINIMUM_VISIBLE_PERCENT = 0.02;
  const BALLOON_OFFSET = 20;
  const MAX_TOOLTIP_ITEMS = 12;
  const AXES_FONT_STYLE = "300 10px";
  const AXES_MAX_COLUMN_WIDTH = 45;
  const AXES_MAX_ROW_HEIGHT = 50;
  const X_AXIS_HEIGHT = 30;
  const X_AXIS_SHIFT_START = 1;
  const Y_AXIS_ZERO_BASED_THRESHOLD = 0.1;
  const MINIMAP_HEIGHT = 40;
  const MINIMAP_MARGIN = 10;
  const MINIMAP_LINE_WIDTH = 1;
  const MINIMAP_EAR_WIDTH = 8;
  const MINIMAP_MAX_ANIMATED_DATASETS = 4;
  const ZOOM_TIMEOUT = TRANSITION_DEFAULT_DURATION;
  const ZOOM_RANGE_DELTA = 0.1;
  const ZOOM_RANGE_MIDDLE = 0.5;
  const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const WEEK_DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  const WEEK_DAYS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const MILISECONDS_IN_DAY = 24 * 60 * 60 * 1e3;
  const SPEED_TEST_INTERVAL = 200;
  const SPEED_TEST_FAST_FPS = 4;
  const SIMPLIFIER_MIN_POINTS = 1e3;
  const SIMPLIFIER_PLOT_FACTOR = 1;
  const SIMPLIFIER_MINIMAP_FACTOR = 0.5;
  const ANIMATE_PROPS = [
    // Viewport X-axis
    "begin 200 fast",
    "end 200 fast",
    "labelFromIndex 200 fast floor",
    "labelToIndex 200 fast ceil",
    // X-axis labels
    "xAxisScale 400",
    // Viewport Y-axis
    "yMinViewport",
    "yMaxViewport",
    "yMinViewportSecond",
    "yMaxViewportSecond",
    // Minimap Y-axis
    "yMinMinimap",
    "yMaxMinimap",
    "yMinMinimapSecond",
    "yMaxMinimapSecond",
    // Y-axis labels
    "yAxisScale",
    "yAxisScaleSecond"
  ];
  function transition(t) {
    return 1 - Math.pow(1 - t, 3);
  }
  function createTransitionManager(onTick) {
    const _transitions = {};
    let _nextFrame = null;
    let _testStartedAt = null;
    let _fps = null;
    let _testingFps = null;
    let _slowDetectedAt = null;
    let _startedAsSlow = null;
    function add(prop, from, to, duration, options) {
      _transitions[prop] = {
        from,
        to,
        duration,
        options,
        current: from,
        startedAt: Date.now(),
        progress: 0
      };
      if (!_nextFrame) {
        _resetSpeedTest();
        _nextFrame = requestAnimationFrame(_tick);
      }
    }
    function remove(prop) {
      delete _transitions[prop];
      if (!isRunning()) {
        cancelAnimationFrame(_nextFrame);
        _nextFrame = null;
      }
    }
    function get(prop) {
      return _transitions[prop];
    }
    function getState() {
      const state = {};
      Object.keys(_transitions).forEach((prop) => {
        const { current, from, to, progress } = _transitions[prop];
        state[prop] = current;
        state[`${prop}From`] = from;
        state[`${prop}To`] = to;
        state[`${prop}Progress`] = progress;
      });
      return state;
    }
    function isRunning() {
      return Boolean(Object.keys(_transitions).length);
    }
    function isFast(forceCheck) {
      if (!forceCheck && (_startedAsSlow || _slowDetectedAt)) {
        return false;
      }
      return _fps === null || _fps >= SPEED_TEST_FAST_FPS;
    }
    function _tick() {
      const isSlow = !isFast();
      _speedTest();
      const state = {};
      Object.keys(_transitions).forEach((prop) => {
        const { startedAt, from, to, duration = TRANSITION_DEFAULT_DURATION, options } = _transitions[prop];
        const progress = Math.min(1, (Date.now() - startedAt) / duration);
        let current = from + (to - from) * transition(progress);
        if (options.includes("ceil")) {
          current = Math.ceil(current);
        } else if (options.includes("floor")) {
          current = Math.floor(current);
        }
        _transitions[prop].current = current;
        _transitions[prop].progress = progress;
        state[prop] = current;
        if (progress === 1) {
          remove(prop);
        }
      });
      if (!isSlow) {
        onTick(state);
      }
      if (isRunning()) {
        _nextFrame = requestAnimationFrame(_tick);
      }
    }
    function _resetSpeedTest() {
      _testStartedAt = null;
      _testingFps = null;
      if (_slowDetectedAt && Date.now() - _slowDetectedAt > 5e3) {
        _slowDetectedAt = null;
      }
      _startedAsSlow = Boolean(_slowDetectedAt) || !isFast(true);
    }
    function _speedTest() {
      if (!_testStartedAt || Date.now() - _testStartedAt >= SPEED_TEST_INTERVAL) {
        if (_testingFps) {
          _fps = _testingFps;
          if (!_slowDetectedAt && !isFast(true)) {
            _slowDetectedAt = Date.now();
          }
        }
        _testStartedAt = Date.now();
        _testingFps = 0;
      } else {
        _testingFps++;
      }
    }
    return { add, remove, get, getState, isRunning, isFast };
  }
  function getMaxMin(array) {
    const length = array.length;
    let max = array[0];
    let min = array[0];
    for (let i = 0; i < length; i++) {
      const value = array[i];
      if (value > max) {
        max = value;
      } else if (value < min) {
        min = value;
      }
    }
    return { max, min };
  }
  function mergeArrays(arrays) {
    return [].concat.apply([], arrays);
  }
  function sumArrays(arrays) {
    const sums = [];
    const n = arrays.length;
    for (let i = 0, l = arrays[0].length; i < l; i++) {
      sums[i] = 0;
      for (let j = 0; j < n; j++) {
        sums[i] += arrays[j][i];
      }
    }
    return sums;
  }
  function proxyMerge(obj1, obj2) {
    return new Proxy({}, {
      get: (obj, prop) => {
        if (obj[prop] !== void 0) {
          return obj[prop];
        } else if (obj2[prop] !== void 0) {
          return obj2[prop];
        } else {
          return obj1[prop];
        }
      }
    });
  }
  function throttle(fn, ms, shouldRunFirst = true) {
    let interval = null;
    let isPending;
    let args;
    return (..._args) => {
      isPending = true;
      args = _args;
      if (!interval) {
        if (shouldRunFirst) {
          isPending = false;
          fn(...args);
        }
        interval = window.setInterval(() => {
          if (!isPending) {
            window.clearInterval(interval);
            interval = null;
            return;
          }
          isPending = false;
          fn(...args);
        }, ms);
      }
    };
  }
  function throttleWithRaf(fn) {
    let waiting = false;
    let args;
    return function(..._args) {
      args = _args;
      if (!waiting) {
        waiting = true;
        requestAnimationFrame(() => {
          waiting = false;
          fn(...args);
        });
      }
    };
  }
  function debounce(fn, ms, shouldRunFirst = true, shouldRunLast = true) {
    let waitingTimeout = null;
    return function() {
      if (waitingTimeout) {
        clearTimeout(waitingTimeout);
        waitingTimeout = null;
      } else if (shouldRunFirst) {
        fn();
      }
      waitingTimeout = setTimeout(() => {
        if (shouldRunLast) {
          fn();
        }
        waitingTimeout = null;
      }, ms);
    };
  }
  function xScaleLevelToStep(scaleLevel) {
    return Math.pow(2, scaleLevel);
  }
  function xStepToScaleLevel(step) {
    return Math.ceil(Math.log2(step || 1));
  }
  const SCALE_LEVELS = [
    1,
    2,
    8,
    18,
    50,
    100,
    250,
    500,
    1e3,
    2500,
    5e3,
    1e4,
    25e3,
    5e4,
    1e5,
    25e4,
    5e5,
    1e6,
    25e5,
    5e6,
    1e7,
    25e6,
    5e7,
    1e8
  ];
  function yScaleLevelToStep(scaleLevel) {
    return SCALE_LEVELS[scaleLevel] || SCALE_LEVELS[SCALE_LEVELS.length - 1];
  }
  function yStepToScaleLevel(neededStep) {
    return SCALE_LEVELS.findIndex((step) => step >= neededStep) || SCALE_LEVELS.length - 1;
  }
  function applyYEdgeOpacity(opacity, xPx, plotWidth) {
    const edgeOffset = Math.min(xPx + GUTTER, plotWidth - xPx);
    if (edgeOffset <= GUTTER * 4) {
      opacity = Math.min(1, opacity, edgeOffset / (GUTTER * 4));
    }
    return opacity;
  }
  function applyXEdgeOpacity(opacity, yPx) {
    return yPx - GUTTER <= GUTTER * 2 ? Math.min(1, opacity, (yPx - GUTTER) / (GUTTER * 2)) : opacity;
  }
  function getPieRadius(projection) {
    return Math.min(...projection.getSize()) * PLOT_PIE_RADIUS_FACTOR;
  }
  function getPieTextSize(percent, radius) {
    return (radius + percent * 200) / 10;
  }
  function getPieTextShift(percent, radius, shift) {
    return percent >= 0.99 ? 0 : Math.min(1 - Math.log(percent * 30) / 5, 4 / 5) * radius;
  }
  function isDataRange(labelFrom, labelTo) {
    return Math.abs(labelTo.value - labelFrom.value) > MILISECONDS_IN_DAY;
  }
  function getSimplificationDelta(pointsLength) {
    return pointsLength >= SIMPLIFIER_MIN_POINTS ? Math.min(pointsLength / 1e3, 1) : 0;
  }
  function createStateManager(data, viewportSize, callback) {
    const _range = { begin: 0, end: 1 };
    const _filter = _buildDefaultFilter();
    const _transitionConfig = _buildTransitionConfig();
    const _transitions = createTransitionManager(_runCallback);
    const _runCallbackOnRaf = throttleWithRaf(_runCallback);
    let _state = {};
    function update({ range = {}, filter = {}, focusOn, minimapDelta } = {}, noTransition) {
      Object.assign(_range, range);
      Object.assign(_filter, filter);
      const prevState = _state;
      _state = calculateState(data, viewportSize, _range, _filter, focusOn, minimapDelta, prevState);
      if (!noTransition) {
        _transitionConfig.forEach(({ prop, duration, options }) => {
          const transition2 = _transitions.get(prop);
          const currentTarget = transition2 ? transition2.to : prevState[prop];
          if (currentTarget !== void 0 && currentTarget !== _state[prop]) {
            const current = transition2 ? options.includes("fast") ? prevState[prop] : transition2.current : prevState[prop];
            if (transition2) {
              _transitions.remove(prop);
            }
            _transitions.add(prop, current, _state[prop], duration, options);
          }
        });
      }
      if (!_transitions.isRunning() || !_transitions.isFast()) {
        _runCallbackOnRaf();
      }
    }
    function hasAnimations() {
      return _transitions.isFast();
    }
    function _buildTransitionConfig() {
      const transitionConfig = [];
      const datasetVisibilities = data.datasets.map(({ key }) => `opacity#${key} ${TRANSITION_DEFAULT_DURATION}`);
      mergeArrays([
        ANIMATE_PROPS,
        datasetVisibilities
      ]).forEach((transition2) => {
        const [prop, duration, ...options] = transition2.split(" ");
        transitionConfig.push({ prop, duration, options });
      });
      return transitionConfig;
    }
    function _buildDefaultFilter() {
      const filter = {};
      data.datasets.forEach(({ key }) => {
        filter[key] = true;
      });
      return filter;
    }
    function _runCallback() {
      const state = _transitions.isFast() ? proxyMerge(_state, _transitions.getState()) : _state;
      state.static = _state;
      callback(state);
    }
    return { update, hasAnimations };
  }
  function calculateState(data, viewportSize, range, filter, focusOn, minimapDelta, prevState) {
    const { begin, end } = range;
    const totalXWidth = data.xLabels.length - 1;
    const labelFromIndex = Math.max(0, Math.ceil(totalXWidth * begin));
    const labelToIndex = Math.min(Math.floor(totalXWidth * end), totalXWidth);
    const xAxisScale = calculateXAxisScale(viewportSize.width, labelFromIndex, labelToIndex);
    const yRanges = data.isStacked ? calculateYRangesStacked(data, filter, labelFromIndex, labelToIndex, prevState) : calculateYRanges(data, filter, labelFromIndex, labelToIndex, prevState);
    const yAxisScale = calculateYAxisScale(viewportSize.height, yRanges.yMinViewport, yRanges.yMaxViewport);
    const yAxisScaleSecond = data.hasSecondYAxis && calculateYAxisScale(viewportSize.height, yRanges.yMinViewportSecond, yRanges.yMaxViewportSecond);
    const yStep = yScaleLevelToStep(yAxisScale);
    yRanges.yMinViewport -= yRanges.yMinViewport % yStep;
    if (yAxisScaleSecond) {
      const yStepSecond = yScaleLevelToStep(yAxisScaleSecond);
      yRanges.yMinViewportSecond -= yRanges.yMinViewportSecond % yStepSecond;
    }
    const datasetsOpacity = {};
    data.datasets.forEach(({ key }) => {
      datasetsOpacity[`opacity#${key}`] = filter[key] ? 1 : 0;
    });
    return Object.assign(
      {
        totalXWidth,
        xAxisScale,
        yAxisScale,
        yAxisScaleSecond,
        labelFromIndex: Math.max(0, labelFromIndex - 1),
        labelToIndex: Math.min(labelToIndex + 1, totalXWidth),
        filter: Object.assign({}, filter),
        focusOn: focusOn !== void 0 ? focusOn : prevState.focusOn,
        minimapDelta: minimapDelta !== void 0 ? minimapDelta : prevState.minimapDelta
      },
      yRanges,
      datasetsOpacity,
      range
    );
  }
  function calculateYRanges(data, filter, labelFromIndex, labelToIndex, prevState) {
    const secondaryYAxisDataset = data.hasSecondYAxis && data.datasets.slice(-1)[0];
    const filteredDatasets = data.datasets.filter((d) => filter[d.key] && d !== secondaryYAxisDataset);
    const yRanges = calculateYRangesForGroup(data, labelFromIndex, labelToIndex, prevState, filteredDatasets);
    if (secondaryYAxisDataset) {
      const {
        yMinViewport: yMinViewportSecond,
        yMaxViewport: yMaxViewportSecond,
        yMinMinimap: yMinMinimapSecond,
        yMaxMinimap: yMaxMinimapSecond
      } = calculateYRangesForGroup(data, labelFromIndex, labelToIndex, prevState, [secondaryYAxisDataset]);
      Object.assign(yRanges, {
        yMinViewportSecond,
        yMaxViewportSecond,
        yMinMinimapSecond,
        yMaxMinimapSecond
      });
    }
    return yRanges;
  }
  function calculateYRangesForGroup(data, labelFromIndex, labelToIndex, prevState, datasets) {
    const { min: yMinMinimapReal = prevState.yMinMinimap, max: yMaxMinimap = prevState.yMaxMinimap } = getMaxMin(mergeArrays(datasets.map(({ yMax, yMin }) => [yMax, yMin])));
    const yMinMinimap = yMinMinimapReal / yMaxMinimap > Y_AXIS_ZERO_BASED_THRESHOLD ? yMinMinimapReal : 0;
    let yMinViewport;
    let yMaxViewport;
    if (labelFromIndex === 0 && labelToIndex === data.xLabels.length - 1) {
      yMinViewport = yMinMinimap;
      yMaxViewport = yMaxMinimap;
    } else {
      const filteredValues = datasets.map(({ values }) => values);
      const viewportValues = filteredValues.map((values) => values.slice(labelFromIndex, labelToIndex + 1));
      const viewportMaxMin = getMaxMin(mergeArrays(viewportValues));
      const yMinViewportReal = viewportMaxMin.min !== void 0 ? viewportMaxMin.min : prevState.yMinViewport;
      yMaxViewport = viewportMaxMin.max !== void 0 ? viewportMaxMin.max : prevState.yMaxViewport;
      yMinViewport = yMinViewportReal / yMaxViewport > Y_AXIS_ZERO_BASED_THRESHOLD ? yMinViewportReal : 0;
    }
    return {
      yMinViewport,
      yMaxViewport,
      yMinMinimap,
      yMaxMinimap
    };
  }
  function calculateYRangesStacked(data, filter, labelFromIndex, labelToIndex, prevState) {
    const filteredDatasets = data.datasets.filter((d) => filter[d.key]);
    const filteredValues = filteredDatasets.map(({ values }) => values);
    const sums = filteredValues.length ? sumArrays(filteredValues) : [];
    const { max: yMaxMinimap = prevState.yMaxMinimap } = getMaxMin(sums);
    const { max: yMaxViewport = prevState.yMaxViewport } = getMaxMin(sums.slice(labelFromIndex, labelToIndex + 1));
    return {
      yMinViewport: 0,
      yMaxViewport,
      yMinMinimap: 0,
      yMaxMinimap
    };
  }
  function calculateXAxisScale(plotWidth, labelFromIndex, labelToIndex) {
    const viewportLabelsCount = labelToIndex - labelFromIndex;
    const maxColumns = Math.floor(plotWidth / AXES_MAX_COLUMN_WIDTH);
    return xStepToScaleLevel(viewportLabelsCount / maxColumns);
  }
  function calculateYAxisScale(plotHeight, yMin, yMax) {
    const availableHeight = plotHeight - X_AXIS_HEIGHT;
    const viewportLabelsCount = yMax - yMin;
    const maxRows = Math.floor(availableHeight / AXES_MAX_ROW_HEIGHT);
    return yStepToScaleLevel(viewportLabelsCount / maxRows);
  }
  const createElement = (tagName = "div") => {
    return document.createElement(tagName);
  };
  function addEventListener(element, event, cb) {
    element.addEventListener(event, cb);
  }
  function removeEventListener(element, event, cb) {
    element.removeEventListener(event, cb);
  }
  function toggleText(element, newText, className = "", inverse = false) {
    const container = element.parentNode;
    container.classList.add("lovely-chart--transition-container");
    const newElement = createElement(element.tagName);
    newElement.className = `${className} lovely-chart--transition lovely-chart--position-${inverse ? "top" : "bottom"} lovely-chart--state-hidden`;
    newElement.innerHTML = newText;
    const selector = className.length ? `.${className.split(" ").join(".")}` : "";
    const oldElements = container.querySelectorAll(`${selector}.lovely-chart--state-hidden`);
    oldElements.forEach((e) => e.remove());
    element.classList.add("lovely-chart--transition");
    element.classList.remove("lovely-chart--position-bottom", "lovely-chart--position-top");
    element.classList.add(inverse ? "lovely-chart--position-bottom" : "lovely-chart--position-top");
    container.insertBefore(newElement, element.nextSibling);
    toggleElementIn(newElement);
    toggleElementOut(element);
    return newElement;
  }
  function toggleElementIn(element) {
    element.classList.remove("lovely-chart--state-animated");
    element.classList.add("lovely-chart--state-animated");
    element.classList.remove("lovely-chart--state-hidden");
  }
  function toggleElementOut(element) {
    element.classList.remove("lovely-chart--state-animated");
    element.classList.add("lovely-chart--state-animated");
    element.classList.add("lovely-chart--state-hidden");
  }
  function createHeader(container, title, zoomOutLabel = "Zoom out", zoomOutCallback) {
    let _element;
    let _titleElement;
    let _zoomOutElement;
    let _captionElement;
    let _isZooming;
    const setCaptionThrottled = throttle(setCaption, 100, false);
    _setupLayout();
    function setCaption(caption) {
      if (_isZooming) {
        return;
      }
      _captionElement.innerHTML = caption;
    }
    function zoom(caption) {
      _zoomOutElement = toggleText(_titleElement, zoomOutLabel, "lovely-chart--header-title lovely-chart--header-zoom-out-control");
      setTimeout(() => {
        addEventListener(_zoomOutElement, "click", _onZoomOut);
      }, 500);
      setCaption(caption);
    }
    function toggleIsZooming(isZooming) {
      _isZooming = isZooming;
    }
    function _setupLayout() {
      _element = createElement();
      _element.className = "lovely-chart--header";
      _titleElement = createElement();
      _titleElement.className = "lovely-chart--header-title";
      _titleElement.innerHTML = title;
      _element.appendChild(_titleElement);
      _captionElement = createElement();
      _captionElement.className = "lovely-chart--header-caption lovely-chart--position-right";
      _element.appendChild(_captionElement);
      container.appendChild(_element);
    }
    function _onZoomOut() {
      _titleElement = toggleText(_zoomOutElement, title, "lovely-chart--header-title", true);
      _titleElement.classList.remove("lovely-chart--transition");
      zoomOutCallback();
    }
    return {
      setCaption: setCaptionThrottled,
      zoom,
      toggleIsZooming
    };
  }
  function statsFormatDayHour(labels) {
    return labels.map((value) => ({
      value,
      text: `${value}:00`
    }));
  }
  function statsFormatDayHourFull(value) {
    return `${value}:00`;
  }
  function statsFormatDay(labels) {
    return labels.map((value) => {
      const date = new Date(value);
      const day = date.getDate();
      const month = MONTHS[date.getMonth()];
      return {
        value,
        text: `${day} ${month}`
      };
    });
  }
  function statsFormatMin(labels) {
    return labels.map((value) => ({
      value,
      text: new Date(value).toString().match(/(\d+:\d+):/)[1]
    }));
  }
  function statsFormatText(labels) {
    return labels.map((value, i) => {
      return {
        value: i,
        text: value
      };
    });
  }
  function humanize(value, decimals = 1) {
    if (value >= 1e6) {
      return keepThreeDigits(value / 1e6, decimals) + "M";
    } else if (value >= 1e3) {
      return keepThreeDigits(value / 1e3, decimals) + "K";
    }
    return value;
  }
  function keepThreeDigits(value, decimals) {
    return value.toFixed(decimals).replace(/(\d{3,})\.\d+/, "$1").replace(/\.0+$/, "");
  }
  function formatInteger(n) {
    if (!Number.isInteger(n)) {
      const abs = Math.abs(n);
      const decimals = abs > 0 && abs < 1 ? Math.max(2, -Math.floor(Math.log10(abs)) + 1) : 2;
      const [intPart, decPart] = n.toFixed(decimals).split(".");
      const trimmed = decPart.replace(/0+$/, "");
      return trimmed ? addThousandSeparators(intPart) + "." + trimmed : addThousandSeparators(intPart);
    }
    return addThousandSeparators(String(n));
  }
  function addThousandSeparators(s) {
    return s.replace(/\d(?=(\d{3})+$)/g, "$& ");
  }
  function getFullLabelDate(label, { isShort = false } = {}) {
    return getLabelDate(label, { isShort, displayWeekDay: true });
  }
  function getLabelDate(label, { isShort = false, displayWeekDay = false, displayYear = true, displayHours = false } = {}) {
    const { value } = label;
    const date = new Date(value);
    const weekDaysArray = isShort ? WEEK_DAYS_SHORT : WEEK_DAYS;
    let string = `${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]}`;
    if (displayWeekDay) {
      string = `${weekDaysArray[date.getUTCDay()]}, ` + string;
    }
    if (displayYear) {
      string += ` ${date.getUTCFullYear()}`;
    }
    if (displayHours) {
      string += `, ${("0" + date.getUTCHours()).slice(-2)}:${("0" + date.getUTCMinutes()).slice(-2)}`;
    }
    return string;
  }
  function getLabelTime(label) {
    return new Date(label.value).toString().match(/(\d+:\d+):/)[1];
  }
  function detectSkin() {
    return document.documentElement.classList.contains("theme-dark") ? "skin-night" : "skin-day";
  }
  let skin = detectSkin();
  const COLORS = {
    "skin-day": {
      "background": "#FFFFFF",
      "text-color": "#222222",
      "minimap-mask": "#E2EEF9/0.6",
      "minimap-slider": "#C0D1E1",
      "grid-lines": "#182D3B/0.1",
      "zoom-out-text": "#108BE3",
      "tooltip-background": "#FFFFFF",
      "tooltip-arrow": "#D2D5D7",
      "mask": "#FFFFFF/0.5",
      "x-axis-text": "#252529/0.6",
      "y-axis-text": "#252529/0.6"
    },
    "skin-night": {
      "background": "#242F3E",
      "text-color": "#FFFFFF",
      "minimap-mask": "#304259/0.6",
      "minimap-slider": "#56626D",
      "grid-lines": "#FFFFFF/0.1",
      "zoom-out-text": "#48AAF0",
      "tooltip-background": "#1c2533",
      "tooltip-arrow": "#D2D5D7",
      "mask": "#242F3E/0.5",
      "x-axis-text": "#A3B1C2/0.6",
      "y-axis-text": "#A3B1C2/0.6"
    }
  };
  const styleElement = document.createElement("style");
  styleElement.type = "text/css";
  styleElement.appendChild(document.createTextNode(""));
  document.head.appendChild(styleElement);
  const styleSheet = styleElement.sheet;
  new MutationObserver(() => {
    skin = detectSkin();
  }).observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
  function createColors(datasetColors) {
    const colors = {};
    const baseClass = `.lovely-chart--color`;
    ["skin-day", "skin-night"].forEach((skin2) => {
      colors[skin2] = {};
      Object.keys(COLORS[skin2]).forEach((prop) => {
        colors[skin2][prop] = hexToChannels(COLORS[skin2][prop]);
      });
      Object.keys(datasetColors).forEach((key) => {
        colors[skin2][`dataset#${key}`] = hexToChannels(datasetColors[key]);
        addCssRule(styleSheet, `.lovely-chart--tooltip-dataset-value${baseClass}-${datasetColors[key].slice(1)}`, `color: ${datasetColors[key]}`);
        addCssRule(styleSheet, `.lovely-chart--button${baseClass}-${datasetColors[key].slice(1)}`, `border-color: ${datasetColors[key]}; color: ${datasetColors[key]}`);
        const checkedBtnSelector = `.lovely-chart--button.lovely-chart--state-checked${baseClass}-${datasetColors[key].slice(1)}`;
        addCssRule(styleSheet, checkedBtnSelector, `background-color: ${datasetColors[key]}`);
      });
    });
    return colors;
  }
  function getCssColor(colors, key, opacity) {
    return buildCssColor(colors[skin][key], opacity);
  }
  function hexToChannels(hexWithAlpha) {
    const [hex, alpha] = hexWithAlpha.replace("#", "").split("/");
    return [
      parseInt(hex.slice(0, 2), 16),
      parseInt(hex.slice(2, 4), 16),
      parseInt(hex.slice(4, 6), 16),
      alpha ? parseFloat(alpha) : 1
    ];
  }
  function buildCssColor([r, g, b, a = 1], opacity = 1) {
    return `rgba(${r}, ${g}, ${b}, ${a * opacity})`;
  }
  function isColorCloseToBackground(colors, hex) {
    const bg = colors[skin]["tooltip-background"];
    const fg = hexToChannels(hex);
    return colorDistance(bg, fg) < 70;
  }
  function isColorCloseToWhite(hex) {
    return colorDistance(hexToChannels(hex), [255, 255, 255]) < 70;
  }
  function colorDistance([r1, g1, b1], [r2, g2, b2]) {
    return Math.sqrt((r1 - r2) ** 2 + (g1 - g2) ** 2 + (b1 - b2) ** 2);
  }
  function addCssRule(sheet, selector, rule) {
    sheet.insertRule(`${selector} { ${rule} }`, sheet.cssRules.length);
  }
  function createProjection(params) {
    const {
      begin,
      end,
      totalXWidth,
      yMin,
      yMax,
      availableWidth,
      availableHeight,
      xPadding = 0,
      yPadding = 0
    } = params;
    let effectiveWidth = availableWidth;
    if (begin === 0) {
      effectiveWidth -= xPadding;
    }
    if (end === 1) {
      effectiveWidth -= xPadding;
    }
    const xFactor = effectiveWidth / ((end !== begin ? end - begin : 1) * totalXWidth);
    let xOffsetPx = begin * totalXWidth * xFactor;
    if (begin === 0) {
      xOffsetPx -= xPadding;
    }
    const effectiveHeight = availableHeight - yPadding;
    const yFactor = effectiveHeight / (yMax - yMin);
    const yOffsetPx = yMin * yFactor;
    function getState() {
      return { xFactor, xOffsetPx, availableHeight, yFactor, yOffsetPx };
    }
    function findClosestLabelIndex(xPx) {
      return Math.round((xPx + xOffsetPx) / xFactor);
    }
    function copy(overrides, cons) {
      return createProjection(proxyMerge(params, overrides));
    }
    function getCenter() {
      return [
        availableWidth / 2,
        availableHeight - effectiveHeight / 2
      ];
    }
    function getSize() {
      return [availableWidth, effectiveHeight];
    }
    function getParams() {
      return params;
    }
    return {
      findClosestLabelIndex,
      copy,
      getCenter,
      getSize,
      getParams,
      getState
    };
  }
  function toPixels(projection, labelIndex, value) {
    const { xFactor, xOffsetPx, availableHeight, yFactor, yOffsetPx } = projection.getState();
    return [
      labelIndex * xFactor - xOffsetPx,
      availableHeight - (value * yFactor - yOffsetPx)
    ];
  }
  function getAxesFont(context) {
    const fontFamily = getComputedStyle(context.canvas).fontFamily || "sans-serif";
    return `${AXES_FONT_STYLE} ${fontFamily}`;
  }
  function createAxes(context, data, plotSize, colors) {
    function drawXAxis(state, projection) {
      context.clearRect(0, plotSize.height - X_AXIS_HEIGHT + 1, plotSize.width, X_AXIS_HEIGHT + 1);
      const topOffset = plotSize.height - X_AXIS_HEIGHT / 2;
      const scaleLevel = Math.floor(state.xAxisScale);
      const step = xScaleLevelToStep(scaleLevel);
      const opacityFactor = 1 - (state.xAxisScale - scaleLevel);
      context.font = getAxesFont(context);
      context.textAlign = "center";
      context.textBaseline = "middle";
      for (let i = state.labelFromIndex; i <= state.labelToIndex; i++) {
        const shiftedI = i - X_AXIS_SHIFT_START;
        if (shiftedI % step !== 0) {
          continue;
        }
        const label = data.xLabels[i];
        const [xPx] = toPixels(projection, i, 0);
        let opacity = shiftedI % (step * 2) === 0 ? 1 : opacityFactor;
        opacity = applyYEdgeOpacity(opacity, xPx, plotSize.width);
        context.fillStyle = getCssColor(colors, "x-axis-text", opacity);
        context.fillText(label.text, xPx, topOffset);
      }
    }
    function drawYAxis(state, projection, secondaryProjection) {
      const {
        yAxisScale,
        yAxisScaleFrom,
        yAxisScaleTo,
        yAxisScaleProgress = 0,
        yMinViewport,
        yMinViewportFrom,
        yMinViewportTo,
        yMaxViewport,
        yMaxViewportFrom,
        yMaxViewportTo,
        yMinViewportSecond,
        yMinViewportSecondFrom,
        yMinViewportSecondTo,
        yMaxViewportSecond,
        yMaxViewportSecondFrom,
        yMaxViewportSecondTo
      } = state;
      const colorKey = secondaryProjection && `dataset#${data.datasets[0].key}`;
      const isYChanging = yMinViewportFrom !== void 0 || yMaxViewportFrom !== void 0;
      if (data.isPercentage) {
        _drawYAxisPercents(projection);
      } else if (data.secondaryYAxis) {
        _drawYAxisScaled(
          state,
          projection,
          Math.round(yAxisScaleTo || yAxisScale),
          yMinViewportTo !== void 0 ? yMinViewportTo : yMinViewport,
          yMaxViewportTo !== void 0 ? yMaxViewportTo : yMaxViewport,
          yAxisScaleFrom ? yAxisScaleProgress : 1
        );
        _drawSecondaryYAxis(
          state,
          projection,
          Math.round(yAxisScaleTo || yAxisScale),
          yMinViewportTo !== void 0 ? yMinViewportTo : yMinViewport,
          yMaxViewportTo !== void 0 ? yMaxViewportTo : yMaxViewport,
          yAxisScaleFrom ? yAxisScaleProgress : 1,
          data.secondaryYAxis
        );
      } else {
        _drawYAxisScaled(
          state,
          projection,
          Math.round(yAxisScaleTo || yAxisScale),
          yMinViewportTo !== void 0 ? yMinViewportTo : yMinViewport,
          yMaxViewportTo !== void 0 ? yMaxViewportTo : yMaxViewport,
          yAxisScaleFrom ? yAxisScaleProgress : 1,
          colorKey
        );
      }
      if (yAxisScaleProgress > 0 && isYChanging) {
        _drawYAxisScaled(
          state,
          projection,
          Math.round(yAxisScaleFrom),
          yMinViewportFrom !== void 0 ? yMinViewportFrom : yMinViewport,
          yMaxViewportFrom !== void 0 ? yMaxViewportFrom : yMaxViewport,
          1 - yAxisScaleProgress,
          colorKey
        );
      }
      if (secondaryProjection) {
        const { yAxisScaleSecond, yAxisScaleSecondFrom, yAxisScaleSecondTo, yAxisScaleSecondProgress = 0 } = state;
        const secondaryColorKey = `dataset#${data.datasets[data.datasets.length - 1].key}`;
        const isYChanging2 = yMinViewportSecondFrom !== void 0 || yMaxViewportSecondFrom !== void 0;
        _drawYAxisScaled(
          state,
          secondaryProjection,
          Math.round(yAxisScaleSecondTo || yAxisScaleSecond),
          yMinViewportSecondTo !== void 0 ? yMinViewportSecondTo : yMinViewportSecond,
          yMaxViewportSecondTo !== void 0 ? yMaxViewportSecondTo : yMaxViewportSecond,
          yAxisScaleSecondFrom ? yAxisScaleSecondProgress : 1,
          secondaryColorKey,
          true
        );
        if (yAxisScaleSecondProgress > 0 && isYChanging2) {
          _drawYAxisScaled(
            state,
            secondaryProjection,
            Math.round(yAxisScaleSecondFrom),
            yMinViewportSecondFrom !== void 0 ? yMinViewportSecondFrom : yMinViewportSecond,
            yMaxViewportSecondFrom !== void 0 ? yMaxViewportSecondFrom : yMaxViewportSecond,
            1 - yAxisScaleSecondProgress,
            secondaryColorKey,
            true
          );
        }
      }
    }
    function _drawYAxisScaled(state, projection, scaleLevel, yMin, yMax, opacity = 1, colorKey = null, isSecondary = false) {
      const step = yScaleLevelToStep(scaleLevel);
      const firstVisibleValue = Math.ceil(yMin / step) * step;
      const lastVisibleValue = Math.floor(yMax / step) * step;
      context.font = getAxesFont(context);
      context.textAlign = isSecondary ? "right" : "left";
      context.textBaseline = "bottom";
      context.lineWidth = 1;
      context.beginPath();
      for (let value = firstVisibleValue; value <= lastVisibleValue; value += step) {
        const [, yPx] = toPixels(projection, 0, value);
        const textOpacity = applyXEdgeOpacity(opacity, yPx);
        context.fillStyle = colorKey ? getCssColor(colors, colorKey, textOpacity) : getCssColor(colors, "y-axis-text", textOpacity);
        const label = isSecondary ? humanize(value) : `${data.valuePrefix || ""}${humanize(value)}${data.valueSuffix || ""}`;
        if (!isSecondary) {
          context.fillText(label, GUTTER, yPx - GUTTER / 2);
        } else {
          context.fillText(label, plotSize.width - GUTTER, yPx - GUTTER / 2);
        }
        if (isSecondary) {
          context.strokeStyle = getCssColor(colors, colorKey, opacity);
          context.moveTo(plotSize.width - GUTTER, yPx);
          context.lineTo(plotSize.width - GUTTER * 2, yPx);
        } else {
          context.moveTo(GUTTER, yPx);
          context.strokeStyle = getCssColor(colors, "grid-lines", opacity);
          context.lineTo(plotSize.width - GUTTER, yPx);
        }
      }
      context.stroke();
    }
    function _drawYAxisPercents(projection) {
      const percentValues = [0, 0.25, 0.5, 0.75, 1];
      const [, height] = projection.getSize();
      context.font = getAxesFont(context);
      context.textAlign = "left";
      context.textBaseline = "bottom";
      context.lineWidth = 1;
      context.beginPath();
      percentValues.forEach((value) => {
        const yPx = height - height * value + PLOT_TOP_PADDING;
        context.fillStyle = getCssColor(colors, "y-axis-text", 1);
        context.fillText(`${value * 100}%`, GUTTER, yPx - GUTTER / 4);
        context.moveTo(GUTTER, yPx);
        context.strokeStyle = getCssColor(colors, "grid-lines", 1);
        context.lineTo(plotSize.width - GUTTER, yPx);
      });
      context.stroke();
    }
    function _drawSecondaryYAxis(state, projection, scaleLevel, yMin, yMax, opacity = 1, secondaryYAxis) {
      const { multiplier, prefix = "", suffix = "" } = secondaryYAxis;
      const step = yScaleLevelToStep(scaleLevel);
      const firstVisibleValue = Math.ceil(yMin / step) * step;
      const lastVisibleValue = Math.floor(yMax / step) * step;
      context.font = getAxesFont(context);
      context.textAlign = "right";
      context.textBaseline = "bottom";
      for (let value = firstVisibleValue; value <= lastVisibleValue; value += step) {
        const [, yPx] = toPixels(projection, 0, value);
        const textOpacity = applyXEdgeOpacity(opacity, yPx);
        const secondaryValue = value * multiplier;
        context.fillStyle = getCssColor(colors, "y-axis-text", textOpacity);
        context.fillText(`${prefix}${humanize(secondaryValue)}${suffix}`, plotSize.width - GUTTER, yPx - GUTTER / 2);
      }
    }
    return { drawXAxis, drawYAxis };
  }
  function setupCanvas(container, { width, height }) {
    const canvas = createElement("canvas");
    canvas.width = width * DPR;
    canvas.height = height * DPR;
    canvas.style.width = "100%";
    canvas.style.height = `${height}px`;
    const context = canvas.getContext("2d");
    context.scale(DPR, DPR);
    container.appendChild(canvas);
    return { canvas, context };
  }
  function clearCanvas(canvas, context) {
    context.clearRect(0, 0, canvas.width, canvas.height);
  }
  function preparePoints(data, datasets, range, visibilities, bounds, pieToArea) {
    let values = datasets.map(({ values: values2 }) => values2.slice(range.from, range.to + 1));
    if (data.isPie && !pieToArea) {
      values = prepareSumsByX(values);
    }
    const points = values.map((datasetValues, i) => datasetValues.map((value, j) => {
      let visibleValue = value;
      if (data.isStacked) {
        visibleValue *= visibilities[i];
      }
      return {
        labelIndex: range.from + j,
        value,
        visibleValue,
        stackOffset: 0,
        stackValue: visibleValue
      };
    }));
    if (data.isPercentage) {
      preparePercentage(points, bounds);
    }
    if (data.isStacked) {
      prepareStacked(points);
    }
    return points;
  }
  function getSumsByY(points) {
    return sumArrays(points.map((datasetPoints) => datasetPoints.map(({ visibleValue }) => visibleValue)));
  }
  function preparePercentage(points, bounds) {
    const sumsByY = getSumsByY(points);
    points.forEach((datasetPoints) => {
      datasetPoints.forEach((point, j) => {
        point.percent = point.visibleValue / sumsByY[j];
        point.visibleValue = point.percent * bounds.yMax;
      });
    });
  }
  function prepareStacked(points) {
    const accum = [];
    points.forEach((datasetPoints) => {
      datasetPoints.forEach((point, j) => {
        if (accum[j] === void 0) {
          accum[j] = 0;
        }
        point.stackOffset = accum[j];
        accum[j] += point.visibleValue;
        point.stackValue = accum[j];
      });
    });
  }
  function prepareSumsByX(values) {
    return values.map((datasetValues) => [datasetValues.reduce((sum, value) => sum + value, 0)]);
  }
  const simplify = (() => {
    function simplify2(points, indexes, fixedPoints) {
      if (points.length < 6) {
        return function() {
          return {
            points,
            indexes,
            removed: []
          };
        };
      }
      let worker = precalculate(points, fixedPoints);
      return function(delta) {
        let result = [], resultIndexes = [], removed = [];
        let delta2 = delta * delta, markers = worker(delta2);
        for (let i = 0, l = points.length; i < l; i++) {
          if (markers[i] >= delta2 || i == 0 || i == l - 1) {
            result.push(points[i]);
            resultIndexes.push(indexes ? indexes[i] : i);
          } else {
            removed.push(i);
          }
        }
        return {
          points: result,
          indexes: resultIndexes,
          removed
        };
      };
    }
    let E1 = 1 / Math.pow(2, 22), MAXLIMIT = 1e5;
    function precalculate(points, fixedPoints) {
      let len = points.length, distances = [], queue = [], maximumDelta;
      for (let i = 0, l = points.length; i < l; ++i) {
        distances[i] = 0;
      }
      if (!fixedPoints) {
        fixedPoints = [];
      }
      let subdivisionTree = 0;
      for (let i = 0, l = fixedPoints.length; i < l; ++i) {
        distances[fixedPoints[i]] = MAXLIMIT;
      }
      function worker(params) {
        let start = params.start, end = params.end, record = params.record, currentLimit = params.currentLimit, usedDistance = 0;
        if (!record) {
          let usedIndex = -1, vector = [
            points[end][0] - points[start][0],
            points[end][1] - points[start][1]
          ];
          for (let i = 0, l = fixedPoints.length; i < l; ++i) {
            let fixId = fixedPoints[i];
            if (fixId > start) {
              if (fixId < end) {
                usedIndex = fixId;
                usedDistance = MAXLIMIT;
                break;
              } else {
                break;
              }
            }
          }
          if (usedIndex < 0) {
            if (Math.abs(vector[0]) > E1 || Math.abs(vector[1]) > E1) {
              let vectorLength = vector[0] * vector[0] + vector[1] * vector[1], vectorLength_1 = 1 / vectorLength;
              for (let i = start + 1; i < end; ++i) {
                let segmentDistance = pointToSegmentDistanceSquare(points[i], points[start], points[end], vector, vectorLength_1);
                if (segmentDistance > usedDistance) {
                  usedIndex = i;
                  usedDistance = segmentDistance;
                }
              }
            } else {
              usedIndex = Math.round((start + end) * 0.5);
              usedDistance = currentLimit;
            }
            distances[usedIndex] = usedDistance;
          }
          record = {
            start,
            end,
            index: usedIndex,
            distance: usedDistance
          };
        }
        if (record.index && record.distance > maximumDelta) {
          if (record.index - start >= 2) {
            queue.push({
              start,
              end: record.index,
              record: record.left,
              currentLimit: record.distance,
              parent: record,
              parentProperty: "left"
            });
          }
          if (end - record.index >= 2) {
            queue.push({
              start: record.index,
              end,
              record: record.right,
              currentLimit: record.distance,
              parent: record,
              parentProperty: "right"
            });
          }
        }
        return record;
      }
      function tick() {
        let request = queue.pop(), result = worker(request);
        if (request.parent && request.parentProperty) {
          request.parent[request.parentProperty] = result;
        }
        return result;
      }
      return function(delta) {
        maximumDelta = delta;
        queue.push({
          start: 0,
          end: len - 1,
          record: subdivisionTree,
          currentLimit: MAXLIMIT
        });
        subdivisionTree = tick();
        while (queue.length) {
          tick();
        }
        return distances;
      };
    }
    function pointToSegmentDistanceSquare(p, v1, v2, dv, dvlen_1) {
      let t;
      let vx = +v1[0], vy = +v1[1];
      t = +((p[0] - vx) * dv[0] + (p[1] - vy) * dv[1]) * dvlen_1;
      if (t > 1) {
        vx = +v2[0];
        vy = +v2[1];
      } else if (t > 0) {
        vx += +dv[0] * t;
        vy += +dv[1] * t;
      }
      let a = +p[0] - vx, b = +p[1] - vy;
      return +a * a + b * b;
    }
    return simplify2;
  })();
  function drawDatasets(context, state, data, range, points, projection, secondaryPoints, secondaryProjection, lineWidth, visibilities, colors, pieToBar, simplification) {
    data.datasets.forEach(({ key, type, hasOwnYAxis }, i) => {
      if (!visibilities[i]) {
        return;
      }
      const options = {
        color: getCssColor(colors, `dataset#${key}`),
        lineWidth,
        opacity: data.isStacked ? 1 : visibilities[i],
        simplification
      };
      const datasetType = type === "pie" && pieToBar ? "bar" : type;
      let datasetPoints = hasOwnYAxis ? secondaryPoints : points[i];
      let datasetProjection = hasOwnYAxis ? secondaryProjection : projection;
      if (datasetType === "area") {
        const bottomLine = [
          { labelIndex: range.from, stackValue: 0 },
          { labelIndex: range.to, stackValue: 0 }
        ];
        const lowerBoundary = points[i - 1] || bottomLine;
        const upperBoundary = points[i].slice().reverse();
        datasetPoints = mergeArrays([lowerBoundary, upperBoundary]);
      }
      if (datasetType === "pie") {
        options.center = projection.getCenter();
        options.radius = getPieRadius(projection);
        options.pointerVector = state.focusOn;
      }
      if (datasetType === "bar") {
        const [x0] = toPixels(projection, 0, 0);
        const [x1] = toPixels(projection, 1, 0);
        options.lineWidth = x1 - x0;
        options.focusOn = state.focusOn;
      }
      drawDataset(datasetType, context, datasetPoints, datasetProjection, options);
    });
    if (state.focusOn && (data.isBars || data.isSteps)) {
      const [x0] = toPixels(projection, 0, 0);
      const [x1] = toPixels(projection, 1, 0);
      drawBarsMask(context, projection, {
        focusOn: state.focusOn,
        color: getCssColor(colors, "mask"),
        lineWidth: data.isSteps ? x1 - x0 + lineWidth : x1 - x0
      });
    }
  }
  function drawDataset(type, ...args) {
    switch (type) {
      case "line":
        return drawDatasetLine(...args);
      case "bar":
        return drawDatasetBars(...args);
      case "step":
        return drawDatasetSteps(...args);
      case "area":
        return drawDatasetArea(...args);
      case "pie":
        return drawDatasetPie(...args);
    }
  }
  function drawDatasetLine(context, points, projection, options) {
    context.beginPath();
    let pixels = [];
    for (let j = 0, l = points.length; j < l; j++) {
      const { labelIndex, stackValue } = points[j];
      pixels.push(toPixels(projection, labelIndex, stackValue));
    }
    if (options.simplification) {
      const simplifierFn = simplify(pixels);
      pixels = simplifierFn(options.simplification).points;
    }
    pixels.forEach(([x, y]) => {
      context.lineTo(x, y);
    });
    context.save();
    context.strokeStyle = options.color;
    context.lineWidth = options.lineWidth;
    context.globalAlpha = options.opacity;
    context.lineJoin = "bevel";
    context.lineCap = "butt";
    context.stroke();
    context.restore();
  }
  function drawDatasetBars(context, points, projection, options) {
    const { yMin } = projection.getParams();
    context.save();
    context.globalAlpha = options.opacity;
    context.fillStyle = options.color;
    for (let j = 0, l = points.length; j < l; j++) {
      const { labelIndex, stackValue, stackOffset = 0 } = points[j];
      const [, yFrom] = toPixels(projection, labelIndex, Math.max(stackOffset, yMin));
      const [x, yTo] = toPixels(projection, labelIndex, stackValue);
      const rectX = x - options.lineWidth / 2;
      const rectY = yTo;
      const rectW = options.opacity === 1 ? options.lineWidth + PLOT_BARS_WIDTH_SHIFT : options.lineWidth + PLOT_BARS_WIDTH_SHIFT * options.opacity;
      const rectH = yFrom - yTo;
      context.fillRect(rectX, rectY, rectW, rectH);
    }
    context.restore();
  }
  function drawDatasetSteps(context, points, projection, options) {
    context.beginPath();
    let pixels = [];
    for (let j = 0, l = points.length; j < l; j++) {
      const { labelIndex, stackValue } = points[j];
      pixels.push(
        toPixels(projection, labelIndex - PLOT_BARS_WIDTH_SHIFT, stackValue),
        toPixels(projection, labelIndex + PLOT_BARS_WIDTH_SHIFT, stackValue)
      );
    }
    pixels.forEach(([x, y]) => {
      context.lineTo(x, y);
    });
    context.save();
    context.strokeStyle = options.color;
    context.lineWidth = options.lineWidth;
    context.globalAlpha = options.opacity;
    context.stroke();
    context.restore();
  }
  function drawBarsMask(context, projection, options) {
    const [xCenter, yCenter] = projection.getCenter();
    const [width, height] = projection.getSize();
    const [x] = toPixels(projection, options.focusOn, 0);
    context.fillStyle = options.color;
    context.fillRect(xCenter - width / 2, yCenter - height / 2, x - options.lineWidth / 2 + PLOT_BARS_WIDTH_SHIFT, height);
    context.fillRect(x + options.lineWidth / 2, yCenter - height / 2, width - (x + options.lineWidth / 2), height);
  }
  function drawDatasetArea(context, points, projection, options) {
    context.beginPath();
    let pixels = [];
    for (let j = 0, l = points.length; j < l; j++) {
      const { labelIndex, stackValue } = points[j];
      pixels.push(toPixels(projection, labelIndex, stackValue));
    }
    if (options.simplification) {
      const simplifierFn = simplify(pixels);
      pixels = simplifierFn(options.simplification).points;
    }
    pixels.forEach(([x, y]) => {
      context.lineTo(x, y);
    });
    context.save();
    context.fillStyle = options.color;
    context.lineWidth = options.lineWidth;
    context.globalAlpha = options.opacity;
    context.lineJoin = "bevel";
    context.lineCap = "butt";
    context.fill();
    context.restore();
  }
  function drawDatasetPie(context, points, projection, options) {
    const { visibleValue, stackValue, stackOffset = 0 } = points[0];
    if (!visibleValue) {
      return;
    }
    const { yMin, yMax } = projection.getParams();
    const percentFactor = 1 / (yMax - yMin);
    const percent = visibleValue * percentFactor;
    const beginAngle = stackOffset * percentFactor * Math.PI * 2 - Math.PI / 2;
    const endAngle = stackValue * percentFactor * Math.PI * 2 - Math.PI / 2;
    const { radius = 120, center: [x, y], pointerVector } = options;
    const shift = pointerVector && beginAngle <= pointerVector.angle && pointerVector.angle < endAngle && pointerVector.distance <= radius ? PLOT_PIE_SHIFT : 0;
    const shiftAngle = (beginAngle + endAngle) / 2;
    const directionX = Math.cos(shiftAngle);
    const directionY = Math.sin(shiftAngle);
    const shiftX = directionX * shift;
    const shiftY = directionY * shift;
    context.save();
    context.beginPath();
    context.fillStyle = options.color;
    context.moveTo(x + shiftX, y + shiftY);
    context.arc(x + shiftX, y + shiftY, radius, beginAngle, endAngle);
    context.lineTo(x + shiftX, y + shiftY);
    context.fill();
    if (percent >= PIE_MINIMUM_VISIBLE_PERCENT) {
      const fontFamily = getComputedStyle(context.canvas).fontFamily || "sans-serif";
      context.font = `700 ${getPieTextSize(percent, radius)}px ${fontFamily}`;
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.fillStyle = "white";
      const textShift = getPieTextShift(percent, radius);
      context.fillText(
        `${Math.round(percent * 100)}%`,
        x + directionX * textShift + shiftX,
        y + directionY * textShift + shiftY
      );
    }
    context.restore();
  }
  function captureEvents(element, options) {
    let captureEvent = null;
    let longPressTimeout = null;
    function onCapture(e) {
      captureEvent = e;
      if (e.type === "mousedown") {
        addEventListener(document, "mousemove", onMove);
        addEventListener(document, "mouseup", onRelease);
      } else if (e.type === "touchstart") {
        addEventListener(document, "touchmove", onMove);
        addEventListener(document, "touchend", onRelease);
        addEventListener(document, "touchcancel", onRelease);
        if (e.pageX === void 0) {
          e.pageX = e.touches[0].pageX;
        }
      }
      if (options.draggingCursor) {
        document.body.classList.add(`cursor-${options.draggingCursor}`);
      }
      options.onCapture && options.onCapture(e);
      if (options.onLongPress) {
        longPressTimeout = setTimeout(() => options.onLongPress(), LONG_PRESS_TIMEOUT);
      }
    }
    function onRelease(e) {
      if (captureEvent) {
        if (longPressTimeout) {
          clearTimeout(longPressTimeout);
          longPressTimeout = null;
        }
        if (options.draggingCursor) {
          document.body.classList.remove(`cursor-${options.draggingCursor}`);
        }
        removeEventListener(document, "mouseup", onRelease);
        removeEventListener(document, "mousemove", onMove);
        removeEventListener(document, "touchcancel", onRelease);
        removeEventListener(document, "touchend", onRelease);
        removeEventListener(document, "touchmove", onMove);
        captureEvent = null;
        options.onRelease && options.onRelease(e);
      }
    }
    function onMove(e) {
      if (captureEvent) {
        if (longPressTimeout) {
          clearTimeout(longPressTimeout);
          longPressTimeout = null;
        }
        if (e.type === "touchmove" && e.pageX === void 0) {
          e.pageX = e.touches[0].pageX;
        }
        options.onDrag && options.onDrag(e, captureEvent, {
          dragOffsetX: e.pageX - captureEvent.pageX
        });
      }
    }
    addEventListener(element, "mousedown", onCapture);
    addEventListener(element, "touchstart", onCapture);
  }
  function createMinimap(container, data, colors, rangeCallback) {
    let _element;
    let _canvas;
    let _context;
    let _canvasSize;
    let _ruler;
    let _slider;
    let _capturedOffset;
    let _range = {};
    let _state;
    const _updateRulerOnRaf = throttleWithRaf(_updateRuler);
    _setupLayout();
    _updateRange(data.minimapRange || DEFAULT_RANGE);
    function update(newState) {
      const { begin, end } = newState;
      if (!_capturedOffset) {
        _updateRange({ begin, end }, true);
      }
      if (data.datasets.length >= MINIMAP_MAX_ANIMATED_DATASETS) {
        newState = newState.static;
      }
      if (!_isStateChanged(newState)) {
        return;
      }
      _state = proxyMerge(newState, { focusOn: null });
      clearCanvas(_canvas, _context);
      _drawDatasets(_state);
    }
    function toggle(shouldShow) {
      _element.classList.toggle("lovely-chart--state-hidden", !shouldShow);
      requestAnimationFrame(() => {
        _element.classList.toggle("lovely-chart--state-transparent", !shouldShow);
      });
    }
    function _setupLayout() {
      _element = createElement();
      _element.className = "lovely-chart--minimap";
      _element.style.height = `${MINIMAP_HEIGHT}px`;
      _setupCanvas();
      _setupRuler();
      container.appendChild(_element);
      _canvasSize = {
        width: _canvas.offsetWidth,
        height: _canvas.offsetHeight
      };
    }
    function _getSize() {
      return {
        width: container.offsetWidth - MINIMAP_MARGIN * 2,
        height: MINIMAP_HEIGHT
      };
    }
    function _setupCanvas() {
      const { canvas, context } = setupCanvas(_element, _getSize());
      _canvas = canvas;
      _context = context;
    }
    function _setupRuler() {
      _ruler = createElement();
      _ruler.className = "lovely-chart--minimap-ruler";
      _ruler.innerHTML = '<div class="lovely-chart--minimap-mask"></div><div class="lovely-chart--minimap-slider"><div class="lovely-chart--minimap-slider-handle"><span class="lovely-chart--minimap-slider-handle-pin"></span></div><div class="lovely-chart--minimap-slider-inner"></div><div class="lovely-chart--minimap-slider-handle"><span class="lovely-chart--minimap-slider-handle-pin"></span></div></div><div class="lovely-chart--minimap-mask"></div>';
      _slider = _ruler.children[1];
      captureEvents(
        _slider.children[1],
        {
          onCapture: _onDragCapture,
          onDrag: _onSliderDrag,
          onRelease: _onDragRelease,
          draggingCursor: "grabbing"
        }
      );
      captureEvents(
        _slider.children[0],
        {
          onCapture: _onDragCapture,
          onDrag: _onLeftEarDrag,
          onRelease: _onDragRelease,
          draggingCursor: "ew-resize"
        }
      );
      captureEvents(
        _slider.children[2],
        {
          onCapture: _onDragCapture,
          onDrag: _onRightEarDrag,
          onRelease: _onDragRelease,
          draggingCursor: "ew-resize"
        }
      );
      _element.appendChild(_ruler);
    }
    function _isStateChanged(newState) {
      if (!_state) {
        return true;
      }
      const { datasets } = data;
      if (datasets.some(({ key }) => _state[`opacity#${key}`] !== newState[`opacity#${key}`])) {
        return true;
      }
      if (_state.yMaxMinimap !== newState.yMaxMinimap) {
        return true;
      }
      return false;
    }
    function _drawDatasets(state = {}) {
      const { datasets } = data;
      const range = {
        from: 0,
        to: state.totalXWidth
      };
      const boundsAndParams = {
        begin: 0,
        end: 1,
        totalXWidth: state.totalXWidth,
        yMin: state.yMinMinimap,
        yMax: state.yMaxMinimap,
        availableWidth: _canvasSize.width,
        availableHeight: _canvasSize.height,
        yPadding: 1
      };
      const visibilities = datasets.map(({ key }) => _state[`opacity#${key}`]);
      const points = preparePoints(data, datasets, range, visibilities, boundsAndParams, true);
      const projection = createProjection(boundsAndParams);
      let secondaryPoints = null;
      let secondaryProjection = null;
      if (data.hasSecondYAxis) {
        const secondaryDataset = datasets.find((d) => d.hasOwnYAxis);
        const bounds = { yMin: state.yMinMinimapSecond, yMax: state.yMaxMinimapSecond };
        secondaryPoints = preparePoints(data, [secondaryDataset], range, visibilities, bounds)[0];
        secondaryProjection = projection.copy(bounds);
      }
      const totalPoints = points.reduce((a, p) => a + p.length, 0);
      const simplification = getSimplificationDelta(totalPoints) * SIMPLIFIER_MINIMAP_FACTOR;
      drawDatasets(
        _context,
        state,
        data,
        range,
        points,
        projection,
        secondaryPoints,
        secondaryProjection,
        MINIMAP_LINE_WIDTH,
        visibilities,
        colors,
        true,
        simplification
      );
    }
    function _onDragCapture(e) {
      e.preventDefault();
      _capturedOffset = e.target.offsetLeft;
    }
    function _onDragRelease() {
      _capturedOffset = null;
    }
    function _onSliderDrag(moveEvent, captureEvent, { dragOffsetX }) {
      const minX1 = 0;
      const maxX1 = _canvasSize.width - _slider.offsetWidth;
      const newX1 = Math.max(minX1, Math.min(_capturedOffset + dragOffsetX - MINIMAP_EAR_WIDTH, maxX1));
      const newX2 = newX1 + _slider.offsetWidth;
      const begin = newX1 / _canvasSize.width;
      const end = newX2 / _canvasSize.width;
      _updateRange({ begin, end });
    }
    function _onLeftEarDrag(moveEvent, captureEvent, { dragOffsetX }) {
      const minX1 = 0;
      const maxX1 = _slider.offsetLeft + _slider.offsetWidth - MINIMAP_EAR_WIDTH * 2;
      const newX1 = Math.min(maxX1, Math.max(minX1, _capturedOffset + dragOffsetX));
      const begin = newX1 / _canvasSize.width;
      _updateRange({ begin });
    }
    function _onRightEarDrag(moveEvent, captureEvent, { dragOffsetX }) {
      const minX2 = _slider.offsetLeft + MINIMAP_EAR_WIDTH * 2;
      const maxX2 = _canvasSize.width;
      const newX2 = Math.max(minX2, Math.min(_capturedOffset + MINIMAP_EAR_WIDTH + dragOffsetX, maxX2));
      const end = newX2 / _canvasSize.width;
      _updateRange({ end });
    }
    function _updateRange(range, isExternal) {
      let nextRange = Object.assign({}, _range, range);
      if (_state && _state.minimapDelta && !isExternal) {
        nextRange = _adjustDiscreteRange(nextRange);
      }
      if (nextRange.begin === _range.begin && nextRange.end === _range.end) {
        return;
      }
      _range = nextRange;
      _updateRulerOnRaf();
      if (!isExternal) {
        rangeCallback(_range);
      }
    }
    function _adjustDiscreteRange(nextRange) {
      const begin = Math.round(nextRange.begin / _state.minimapDelta) * _state.minimapDelta;
      const end = Math.round(nextRange.end / _state.minimapDelta) * _state.minimapDelta;
      return { begin, end };
    }
    function _updateRuler() {
      const { begin, end } = _range;
      _ruler.children[0].style.width = `${begin * 100}%`;
      _ruler.children[1].style.width = `${(end - begin) * 100}%`;
      _ruler.children[2].style.width = `${(1 - end) * 100}%`;
    }
    return { update, toggle };
  }
  function createTooltip(container, data, plotSize, colors, onZoom, onFocus) {
    let _state;
    let _points;
    let _projection;
    let _secondaryPoints;
    let _secondaryProjection;
    let _element;
    let _canvas;
    let _context;
    let _balloon;
    let _offsetX;
    let _offsetY;
    let _clickedOnLabel = null;
    let _isZoomed = false;
    let _isZooming = false;
    const _selectLabelOnRaf = throttleWithRaf(_selectLabel);
    const _throttledUpdateContent = throttle(_updateContent, 100, true);
    _setupLayout();
    function update(state, points, projection, secondaryPoints, secondaryProjection) {
      _state = state;
      _points = points;
      _projection = projection;
      _secondaryPoints = secondaryPoints;
      _secondaryProjection = secondaryProjection;
      _selectLabel(true);
    }
    function toggleLoading(isLoading) {
      _balloon.classList.toggle("lovely-chart--state-loading", isLoading);
      if (!isLoading) {
        _clear();
      }
    }
    function toggleIsZoomed(isZoomed) {
      if (isZoomed !== _isZoomed) {
        _isZooming = true;
      }
      _isZoomed = isZoomed;
      _balloon.classList.toggle("lovely-chart--state-inactive", isZoomed);
    }
    function _setupLayout() {
      _element = createElement();
      _element.className = `lovely-chart--tooltip`;
      _setupCanvas();
      _setupBalloon();
      if ("ontouchstart" in window) {
        addEventListener(_element, "touchmove", _onMouseMove);
        addEventListener(_element, "touchstart", _onMouseMove);
        addEventListener(document, "touchstart", _onDocumentMove);
      } else {
        addEventListener(_element, "mousemove", _onMouseMove);
        addEventListener(_element, "click", _onClick);
        addEventListener(document, "mousemove", _onDocumentMove);
      }
      container.appendChild(_element);
    }
    function _setupCanvas() {
      const { canvas, context } = setupCanvas(_element, plotSize);
      _canvas = canvas;
      _context = context;
    }
    function _setupBalloon() {
      _balloon = createElement();
      _balloon.className = `lovely-chart--tooltip-balloon${!data.isZoomable ? " lovely-chart--state-inactive" : ""}`;
      _balloon.innerHTML = '<div class="lovely-chart--tooltip-title"></div><div class="lovely-chart--tooltip-legend"></div><div class="lovely-chart--spinner"></div>';
      if ("ontouchstart" in window && data.isZoomable) {
        addEventListener(_balloon, "click", _onBalloonClick);
      }
      _element.appendChild(_balloon);
    }
    function _onMouseMove(e) {
      if (e.target === _balloon || _balloon.contains(e.target) || _clickedOnLabel) {
        return;
      }
      _isZooming = false;
      const pageOffset = _getPageOffset(_element);
      _offsetX = (e.touches ? e.touches[0].clientX : e.clientX) - pageOffset.left;
      _offsetY = (e.touches ? e.touches[0].clientY : e.clientY) - pageOffset.top;
      _selectLabelOnRaf();
    }
    function _onDocumentMove(e) {
      if (_offsetX !== null && e.target !== _element && !_element.contains(e.target)) {
        _clear();
      }
    }
    function _onClick(e) {
      if (_isZooming) {
        return;
      }
      if (data.isZoomable) {
        const oldLabelIndex = _clickedOnLabel;
        _clickedOnLabel = null;
        _onMouseMove(e);
        const newLabelIndex = _getLabelIndex();
        if (newLabelIndex !== oldLabelIndex) {
          _clickedOnLabel = newLabelIndex;
        }
        onZoom(newLabelIndex);
      }
    }
    function _onBalloonClick() {
      if (_balloon.classList.contains("lovely-chart--state-inactive")) {
        return;
      }
      const labelIndex = _projection.findClosestLabelIndex(_offsetX);
      onZoom(labelIndex);
    }
    function _clear(isExternal) {
      _offsetX = null;
      _clickedOnLabel = null;
      clearCanvas(_canvas, _context);
      _hideBalloon();
      if (!isExternal && onFocus) {
        onFocus(null);
      }
    }
    function _getLabelIndex() {
      const labelIndex = _projection.findClosestLabelIndex(_offsetX);
      return labelIndex < _state.labelFromIndex || labelIndex > _state.labelToIndex ? null : labelIndex;
    }
    function _selectLabel(isExternal) {
      if (!_offsetX || !_state || _isZooming) {
        return;
      }
      const labelIndex = _getLabelIndex();
      if (labelIndex === null) {
        _clear(isExternal);
        return;
      }
      const pointerVector = getPointerVector();
      const shouldShowBalloon = data.isPie ? pointerVector.distance <= getPieRadius(_projection) : true;
      if (!isExternal && onFocus) {
        if (data.isPie) {
          onFocus(pointerVector);
        } else {
          onFocus(labelIndex);
        }
      }
      function getValue(values, labelIndex2) {
        if (data.isPie) {
          return values.slice(_state.labelFromIndex, _state.labelToIndex + 1).reduce((a, x) => a + x, 0);
        }
        return values[labelIndex2];
      }
      const [xPx] = toPixels(_projection, labelIndex, 0);
      const statistics = data.datasets.map(({ key, name, values, hasOwnYAxis }, i) => ({
        key,
        name,
        value: getValue(values, labelIndex),
        hasOwnYAxis,
        originalIndex: i
      })).filter(({ key }) => _state.filter[key]);
      if (statistics.length && shouldShowBalloon) {
        _updateBalloon(statistics, labelIndex);
      } else {
        _hideBalloon();
      }
      clearCanvas(_canvas, _context);
      if (data.isLines || data.isAreas) {
        if (data.isLines) {
          _drawCircles(statistics, labelIndex);
        }
        _drawTail(xPx, plotSize.height - X_AXIS_HEIGHT, getCssColor(colors, "grid-lines"));
      }
    }
    function _drawCircles(statistics, labelIndex) {
      statistics.forEach(({ value, key, hasOwnYAxis, originalIndex }) => {
        const pointIndex = labelIndex - _state.labelFromIndex;
        const point = hasOwnYAxis ? _secondaryPoints[pointIndex] : _points[originalIndex][pointIndex];
        if (!point) {
          return;
        }
        const [x, y] = hasOwnYAxis ? toPixels(_secondaryProjection, labelIndex, point.stackValue) : toPixels(_projection, labelIndex, point.stackValue);
        _drawCircle(
          [x, y],
          getCssColor(colors, `dataset#${key}`),
          getCssColor(colors, "background")
        );
      });
    }
    function _drawCircle([xPx, yPx], strokeColor, fillColor) {
      _context.strokeStyle = strokeColor;
      _context.fillStyle = fillColor;
      _context.lineWidth = 2;
      _context.beginPath();
      _context.arc(xPx, yPx, 4, 0, 2 * Math.PI);
      _context.fill();
      _context.stroke();
    }
    function _drawTail(xPx, height, color) {
      _context.strokeStyle = color;
      _context.lineWidth = 1;
      _context.beginPath();
      _context.moveTo(xPx, 0);
      _context.lineTo(xPx, height);
      _context.stroke();
    }
    function _getBalloonLeftOffset(labelIndex) {
      const meanLabel = (_state.labelFromIndex + _state.labelToIndex) / 2;
      const { angle } = getPointerVector();
      const shouldPlaceRight = data.isPie ? angle > Math.PI / 2 : labelIndex < meanLabel;
      const leftOffset = shouldPlaceRight ? _offsetX + BALLOON_OFFSET : _offsetX - (_balloon.offsetWidth + BALLOON_OFFSET);
      return Math.min(Math.max(0, leftOffset), container.offsetWidth - _balloon.offsetWidth);
    }
    function _getBalloonTopOffset() {
      return data.isPie ? `${_offsetY}px` : 0;
    }
    function _updateBalloon(statistics, labelIndex) {
      _balloon.style.transform = `translate3D(${_getBalloonLeftOffset(labelIndex)}px, ${_getBalloonTopOffset()}, 0)`;
      _balloon.classList.add("lovely-chart--state-shown");
      if (data.isPie) {
        _updateContent(null, statistics);
      } else {
        _throttledUpdateContent(_getTitle(data, labelIndex), statistics);
      }
    }
    function _getTitle(data2, labelIndex) {
      switch (data2.tooltipFormatter) {
        case "statsFormatDayHourFull":
          return statsFormatDayHourFull(data2.xLabels[labelIndex].value);
        case "statsTooltipFormat('day')":
          return getLabelDate(data2.xLabels[labelIndex]);
        case "statsTooltipFormat('hour')":
        case "statsTooltipFormat('5min')":
          return getLabelTime(data2.xLabels[labelIndex]);
        default:
          return data2.xLabels[labelIndex].text;
      }
    }
    function _isPieSectorSelected(statistics, value, totalValue, index, pointerVector) {
      const offset = index > 0 ? statistics.slice(0, index).reduce((a, x) => a + x.value, 0) : 0;
      const beginAngle = offset / totalValue * Math.PI * 2 - Math.PI / 2;
      const endAngle = (offset + value) / totalValue * Math.PI * 2 - Math.PI / 2;
      return pointerVector && beginAngle <= pointerVector.angle && pointerVector.angle < endAngle && pointerVector.distance <= getPieRadius(_projection);
    }
    function _updateTitle(title) {
      const titleContainer = _balloon.children[0];
      if (data.isPie) {
        if (titleContainer) {
          titleContainer.style.display = "none";
        }
      } else {
        if (titleContainer.style.display === "none") {
          titleContainer.style.display = "";
        }
        const currentTitle = titleContainer.querySelector(":not(.lovely-chart--state-hidden)");
        if (!titleContainer.innerHTML || !currentTitle) {
          titleContainer.innerHTML = `<span>${title}</span>`;
        } else {
          currentTitle.innerHTML = title;
        }
      }
    }
    function _insertNewDataSet(dataSetContainer, { name, key, value }, totalValue) {
      const colorHex = data.colors[key];
      const colorClass = isColorCloseToBackground(colors, colorHex) ? "" : ` lovely-chart--color-${colorHex.slice(1)}`;
      const className = `lovely-chart--tooltip-dataset-value lovely-chart--position-right${colorClass}`;
      const newDataSet = createElement();
      newDataSet.className = "lovely-chart--tooltip-dataset";
      newDataSet.setAttribute("data-present", "true");
      newDataSet.setAttribute("data-name", name);
      newDataSet.innerHTML = `<span class="lovely-chart--dataset-title">${name}</span><span class="${className}">${_formatValue(value)}</span>`;
      _renderPercentageValue(newDataSet, value, totalValue);
      dataSetContainer.appendChild(newDataSet);
    }
    function _updateDataSet(currentDataSet, { key, value } = {}, totalValue) {
      currentDataSet.setAttribute("data-present", "true");
      const valueElement = currentDataSet.querySelector(`.lovely-chart--tooltip-dataset-value`);
      if (valueElement) {
        valueElement.innerHTML = _formatValue(value);
      }
      _renderPercentageValue(currentDataSet, value, totalValue);
    }
    function _formatValue(value) {
      return `${data.valuePrefix || ""}${formatInteger(value)}${data.valueSuffix || ""}`;
    }
    function _renderPercentageValue(dataSet, value, totalValue) {
      if (!data.isPercentage) {
        return;
      }
      if (data.isPie) {
        Array.from(dataSet.querySelectorAll(`.lovely-chart--percentage-title`)).forEach((e) => e.remove());
        return;
      }
      const percentageValue = totalValue ? Math.round(value / totalValue * 100) : 0;
      const percentageElement = dataSet.querySelector(`.lovely-chart--percentage-title:not(.lovely-chart--state-hidden)`);
      if (!percentageElement) {
        const newPercentageTitle = createElement("span");
        newPercentageTitle.className = "lovely-chart--percentage-title lovely-chart--position-left";
        newPercentageTitle.innerHTML = `${percentageValue}%`;
        dataSet.prepend(newPercentageTitle);
      } else {
        percentageElement.innerHTML = `${percentageValue}%`;
      }
    }
    function _updateDataSets(statistics) {
      const dataSetContainer = _balloon.children[1];
      if (data.isPie) {
        dataSetContainer.classList.add("lovely-chart--tooltip-legend-pie");
      }
      Array.from(dataSetContainer.children).forEach((dataSet) => {
        if (!data.isPie && dataSetContainer.classList.contains("lovely-chart--tooltip-legend-pie")) {
          dataSet.remove();
        } else {
          dataSet.setAttribute("data-present", "false");
        }
      });
      const totalValue = statistics.reduce((a, x) => a + x.value, 0);
      const pointerVector = getPointerVector();
      const filteredStatistics = statistics.filter(({ value }) => value !== 0);
      const sortedStatistics = filteredStatistics.sort((a, b) => b.value - a.value);
      const limitedStatistics = sortedStatistics.slice(0, MAX_TOOLTIP_ITEMS);
      const finalStatistics = data.isPie ? limitedStatistics.filter(({ value }, index) => _isPieSectorSelected(statistics, value, totalValue, index, pointerVector)) : limitedStatistics;
      finalStatistics.forEach((statItem) => {
        const currentDataSet = dataSetContainer.querySelector(`[data-name="${statItem.name}"]`);
        if (!currentDataSet) {
          _insertNewDataSet(dataSetContainer, statItem, totalValue);
        } else {
          _updateDataSet(currentDataSet, statItem, totalValue);
          dataSetContainer.appendChild(currentDataSet);
        }
      });
      if ((data.isBars || data.isSteps || data.isAreas) && data.isStacked) {
        _renderTotal(dataSetContainer, _formatValue(totalValue));
      }
      if (data.secondaryYAxis) {
        _renderSecondaryTotal(dataSetContainer, totalValue);
      }
      Array.from(dataSetContainer.querySelectorAll('[data-total="true"]')).forEach((el) => dataSetContainer.appendChild(el));
      Array.from(dataSetContainer.querySelectorAll('[data-present="false"]')).forEach((dataSet) => {
        dataSet.remove();
      });
    }
    function _updateContent(title, statistics) {
      _updateTitle(title);
      _updateDataSets(statistics);
    }
    function _renderTotal(dataSetContainer, totalValue) {
      const totalText = dataSetContainer.querySelector(`[data-total="true"]`);
      const className = `lovely-chart--tooltip-dataset-value lovely-chart--position-right`;
      if (!totalText) {
        const newTotalText = createElement();
        newTotalText.className = "lovely-chart--tooltip-dataset lovely-chart--tooltip-dataset-total";
        newTotalText.setAttribute("data-present", "true");
        newTotalText.setAttribute("data-total", "true");
        newTotalText.innerHTML = `<span>Total</span><span class="${className}">${totalValue}</span>`;
        dataSetContainer.appendChild(newTotalText);
      } else {
        totalText.setAttribute("data-present", "true");
        const valueElement = totalText.querySelector(`.lovely-chart--tooltip-dataset-value:not(.lovely-chart--state-hidden)`);
        valueElement.innerHTML = totalValue;
      }
    }
    function _renderSecondaryTotal(dataSetContainer, totalValue) {
      const { label, multiplier, prefix = "", suffix = "" } = data.secondaryYAxis;
      const totalText = dataSetContainer.querySelector(`[data-total="true"]`);
      const className = `lovely-chart--tooltip-dataset-value lovely-chart--position-right`;
      const secondaryValue = (totalValue * multiplier).toFixed(2);
      if (!totalText) {
        const newTotalText = createElement();
        newTotalText.className = "lovely-chart--tooltip-dataset lovely-chart--tooltip-dataset-total";
        newTotalText.setAttribute("data-present", "true");
        newTotalText.setAttribute("data-total", "true");
        newTotalText.innerHTML = `<span>${label}</span><span class="${className}">${prefix}${secondaryValue}${suffix}</span>`;
        dataSetContainer.appendChild(newTotalText);
      } else {
        totalText.setAttribute("data-present", "true");
        const valueElement = totalText.querySelector(`.lovely-chart--tooltip-dataset-value:not(.lovely-chart--state-hidden)`);
        valueElement.innerHTML = `${prefix}${secondaryValue}${suffix}`;
      }
    }
    function _hideBalloon() {
      _balloon.classList.remove("lovely-chart--state-shown");
    }
    function getPointerVector() {
      const { width, height } = _element.getBoundingClientRect();
      const center = [width / 2, height / 2];
      const angle = Math.atan2(_offsetY - center[1], _offsetX - center[0]);
      const distance = Math.sqrt((_offsetX - center[0]) ** 2 + (_offsetY - center[1]) ** 2);
      return {
        angle: angle >= -Math.PI / 2 ? angle : 2 * Math.PI + angle,
        distance
      };
    }
    function _getPageOffset(el) {
      return el.getBoundingClientRect();
    }
    return { update, toggleLoading, toggleIsZoomed };
  }
  function createTools(container, data, filterCallback) {
    let _element;
    _setupLayout();
    _updateFilter();
    function redraw() {
      if (_element) {
        const oldElement = _element;
        oldElement.classList.add("lovely-chart--state-hidden");
        setTimeout(() => {
          oldElement.parentNode.removeChild(oldElement);
        }, 500);
      }
      _setupLayout();
      _element.classList.add("lovely-chart--state-transparent");
      requestAnimationFrame(() => {
        _element.classList.remove("lovely-chart--state-transparent");
      });
    }
    function _setupLayout() {
      _element = createElement();
      _element.className = "lovely-chart--tools";
      if (data.datasets.length < 2) {
        _element.className += " lovely-chart--state-hidden";
      }
      data.datasets.forEach(({ key, name }) => {
        const control = createElement("a");
        control.href = "#";
        control.dataset.key = key;
        const darkContent = isColorCloseToWhite(data.colors[key]) ? " lovely-chart--dark-content" : "";
        control.className = `lovely-chart--button lovely-chart--color-${data.colors[key].slice(1)} lovely-chart--state-checked${darkContent}`;
        control.innerHTML = `<span class="lovely-chart--button-check"></span><span class="lovely-chart--button-label">${name}</span>`;
        control.addEventListener("click", (e) => {
          e.preventDefault();
          if (!control.dataset.clickPrevented) {
            _updateFilter(control);
          }
          delete control.dataset.clickPrevented;
        });
        captureEvents(control, {
          onLongPress: () => {
            control.dataset.clickPrevented = "true";
            _updateFilter(control, true);
          }
        });
        _element.appendChild(control);
      });
      container.appendChild(_element);
    }
    function _updateFilter(button, isLongPress = false) {
      const buttons = Array.from(_element.getElementsByTagName("a"));
      const isSingleChecked = _element.querySelectorAll(".lovely-chart--state-checked").length === 1;
      if (button) {
        if (button.classList.contains("lovely-chart--state-checked") && isSingleChecked) {
          if (isLongPress) {
            buttons.forEach((b) => b.classList.add("lovely-chart--state-checked"));
            button.classList.remove("lovely-chart--state-checked");
          } else {
            button.classList.remove("lovely-chart--state-shake");
            requestAnimationFrame(() => {
              button.classList.add("lovely-chart--state-shake");
            });
          }
        } else if (isLongPress) {
          buttons.forEach((b) => b.classList.remove("lovely-chart--state-checked"));
          button.classList.add("lovely-chart--state-checked");
        } else {
          button.classList.toggle("lovely-chart--state-checked");
        }
      }
      const filter = {};
      buttons.forEach((input) => {
        filter[input.dataset.key] = input.classList.contains("lovely-chart--state-checked");
      });
      filterCallback(filter);
    }
    return {
      redraw
    };
  }
  const DEFAULT_COLORS = [
    "#3497ED",
    "#2373DB",
    "#9ED448",
    "#5FB641",
    "#F5BD25",
    "#F79E39",
    "#E65850",
    "#5D5CDC"
  ];
  const LABEL_TYPE_TO_FORMATTER = {
    "day": "statsFormat('day')",
    "hour": "statsFormat('hour')",
    "5min": "statsFormat('5min')",
    "dayHour": "statsFormatDayHour",
    "text": void 0
  };
  function analyzeData(data) {
    const { title, labelFormatter: labelFormatterRaw, labelType, tooltipFormatter, isStacked, isPercentage, secondaryYAxis, hasSecondYAxis, onZoom, minimapRange, hideCaption, zoomOutLabel, valuePrefix, valueSuffix } = data;
    const labelFormatter = labelFormatterRaw || labelType && LABEL_TYPE_TO_FORMATTER[labelType];
    const { datasets, labels } = prepareDatasets(data);
    const colors = {};
    let totalYMin = Infinity;
    let totalYMax = -Infinity;
    datasets.forEach(({ key, color, yMin, yMax }) => {
      colors[key] = color;
      if (yMin < totalYMin) {
        totalYMin = yMin;
      }
      if (yMax > totalYMax) {
        totalYMax = yMax;
      }
    });
    let xLabels;
    switch (labelFormatter) {
      case "statsFormatDayHour":
        xLabels = statsFormatDayHour(labels);
        break;
      case "statsFormat('day')":
        xLabels = statsFormatDay(labels);
        break;
      case "statsFormat('hour')":
      case "statsFormat('5min')":
        xLabels = statsFormatMin(labels);
        break;
      default:
        xLabels = statsFormatText(labels);
        break;
    }
    const analyzed = {
      title,
      labelFormatter,
      tooltipFormatter,
      xLabels,
      datasets,
      isStacked,
      isPercentage,
      secondaryYAxis,
      hasSecondYAxis,
      valuePrefix,
      valueSuffix,
      onZoom,
      isLines: data.type === "line",
      isBars: data.type === "bar",
      isSteps: data.type === "step",
      isAreas: data.type === "area",
      isPie: data.type === "pie",
      yMin: totalYMin,
      yMax: totalYMax,
      colors,
      minimapRange,
      hideCaption,
      zoomOutLabel
    };
    analyzed.shouldZoomToPie = !analyzed.onZoom && analyzed.isPercentage;
    analyzed.isZoomable = analyzed.onZoom || analyzed.shouldZoomToPie;
    return analyzed;
  }
  function prepareDatasets(data) {
    const { type, labels, datasets, hasSecondYAxis } = data;
    let nextDefaultColor = 0;
    return {
      labels: cloneArray(labels),
      datasets: datasets.map(({ name, color, values }, i) => {
        const { min: yMin, max: yMax } = getMaxMin(values);
        return {
          type,
          key: `y${i}`,
          name,
          color: color || DEFAULT_COLORS[nextDefaultColor++ % DEFAULT_COLORS.length],
          values: cloneArray(values),
          hasOwnYAxis: hasSecondYAxis && i === datasets.length - 1,
          yMin,
          yMax
        };
      })
    };
  }
  function cloneArray(array) {
    return array.slice(0);
  }
  function createZoomer(data, overviewData, colors, stateManager, container, header, minimap, tooltip, tools) {
    let _isZoomed = false;
    let _stateBeforeZoomIn;
    let _stateBeforeZoomOut;
    function zoomIn(state, labelIndex) {
      if (_isZoomed) {
        return;
      }
      const label = data.xLabels[labelIndex];
      _stateBeforeZoomIn = state;
      header.toggleIsZooming(true);
      tooltip.toggleLoading(true);
      tooltip.toggleIsZoomed(true);
      if (data.shouldZoomToPie) {
        container.classList.add("lovely-chart--state-zoomed-in");
        container.classList.add("lovely-chart--state-animating");
      }
      const { value } = label;
      const dataPromise = data.shouldZoomToPie ? Promise.resolve(_generatePieData(labelIndex)) : data.onZoom(value);
      dataPromise.then((newData) => _replaceData(newData, labelIndex, label));
    }
    function zoomOut(state) {
      if (!_isZoomed) {
        return;
      }
      _stateBeforeZoomOut = state;
      header.toggleIsZooming(true);
      tooltip.toggleLoading(true);
      tooltip.toggleIsZoomed(false);
      if (data.shouldZoomToPie) {
        container.classList.remove("lovely-chart--state-zoomed-in");
        container.classList.add("lovely-chart--state-animating");
      }
      const labelIndex = Math.round((state.labelFromIndex + state.labelToIndex) / 2);
      _replaceData(overviewData, labelIndex);
    }
    function isZoomed() {
      return _isZoomed;
    }
    function _replaceData(newRawData, labelIndex, zoomInLabel) {
      if (!newRawData) {
        tooltip.toggleLoading(false);
        tooltip.toggleIsZoomed(false);
        header.toggleIsZooming(false);
        return;
      }
      tooltip.toggleLoading(false);
      const labelWidth = 1 / data.xLabels.length;
      const labelMiddle = labelIndex / (data.xLabels.length - 1);
      const filter = {};
      data.datasets.forEach(({ key }) => filter[key] = false);
      const newData = analyzeData(newRawData, _isZoomed || data.shouldZoomToPie ? "day" : "hour");
      const shouldZoomToLines = Object.keys(data.datasets).length !== Object.keys(newData.datasets).length;
      stateManager.update({
        range: {
          begin: labelMiddle - labelWidth / 2,
          end: labelMiddle + labelWidth / 2
        },
        filter
      });
      setTimeout(() => {
        Object.assign(data, newData);
        if (shouldZoomToLines && newRawData.colors) {
          Object.assign(colors, createColors(newRawData.colors));
        }
        if (shouldZoomToLines) {
          minimap.toggle(_isZoomed);
          tools.redraw();
          container.style.width = `${container.scrollWidth}px`;
          container.style.height = `${container.scrollHeight}px`;
        }
        stateManager.update({
          range: {
            begin: ZOOM_RANGE_MIDDLE - ZOOM_RANGE_DELTA,
            end: ZOOM_RANGE_MIDDLE + ZOOM_RANGE_DELTA
          },
          focusOn: null
        }, true);
        const daysCount = _isZoomed || data.shouldZoomToPie ? data.xLabels.length : data.xLabels.length / 24;
        const halfDayWidth = 1 / daysCount / 2;
        let range;
        let filter2;
        if (_isZoomed) {
          range = {
            begin: _stateBeforeZoomIn.begin,
            end: _stateBeforeZoomIn.end
          };
          filter2 = shouldZoomToLines ? _stateBeforeZoomIn.filter : _stateBeforeZoomOut.filter;
        } else {
          if (shouldZoomToLines) {
            range = {
              begin: 0,
              end: 1
            };
            filter2 = {};
            data.datasets.forEach(({ key }) => filter2[key] = true);
          } else {
            range = data.shouldZoomToPie ? {
              begin: ZOOM_RANGE_MIDDLE - halfDayWidth,
              end: ZOOM_RANGE_MIDDLE + halfDayWidth
            } : newData.minimapRange;
            filter2 = _stateBeforeZoomIn.filter;
          }
        }
        stateManager.update({
          range,
          filter: filter2,
          minimapDelta: _isZoomed ? null : range.end - range.begin
        });
        if (zoomInLabel) {
          header.zoom(getFullLabelDate(zoomInLabel));
        }
        _isZoomed = !_isZoomed;
        header.toggleIsZooming(false);
      }, stateManager.hasAnimations() ? ZOOM_TIMEOUT : 0);
      setTimeout(() => {
        if (data.shouldZoomToPie) {
          container.classList.remove("lovely-chart--state-animating");
        }
      }, stateManager.hasAnimations() ? 1e3 : 0);
    }
    function _generatePieData(labelIndex) {
      return Object.assign(
        {},
        overviewData,
        {
          type: "pie",
          labels: overviewData.labels.slice(labelIndex - 3, labelIndex + 4),
          datasets: overviewData.datasets.map((dataset) => {
            return {
              ...dataset,
              values: dataset.values.slice(labelIndex - 3, labelIndex + 4)
            };
          })
        }
      );
    }
    return { zoomIn, zoomOut, isZoomed };
  }
  function create(container, originalData) {
    let _stateManager;
    let _element;
    let _plot;
    let _context;
    let _plotSize;
    let _header;
    let _axes;
    let _minimap;
    let _tooltip;
    let _tools;
    let _zoomer;
    let _state;
    let _windowWidth = window.innerWidth;
    const _data = analyzeData(originalData);
    const _colors = createColors(_data.colors);
    const _redrawDebounced = debounce(_redraw, 500, false, true);
    _setupComponents();
    _setupGlobalListeners();
    function _setupComponents() {
      _setupContainer();
      _header = createHeader(_element, _data.title, _data.zoomOutLabel, _onZoomOut);
      _setupPlotCanvas();
      _stateManager = createStateManager(_data, _plotSize, _onStateUpdate);
      _axes = createAxes(_context, _data, _plotSize, _colors);
      _minimap = createMinimap(_element, _data, _colors, _onRangeChange);
      _tooltip = createTooltip(_element, _data, _plotSize, _colors, _onZoomIn, _onFocus);
      _tools = createTools(_element, _data, _onFilterChange);
      _zoomer = _data.isZoomable && createZoomer(_data, originalData, _colors, _stateManager, _element, _header, _minimap, _tooltip, _tools);
    }
    function _setupContainer() {
      _element = createElement();
      _element.className = `lovely-chart--container${_data.shouldZoomToPie ? " lovely-chart--container-type-pie" : ""}`;
      container.appendChild(_element);
    }
    function _setupPlotCanvas() {
      const { canvas, context } = setupCanvas(_element, {
        width: _element.clientWidth,
        height: PLOT_HEIGHT
      });
      _plot = canvas;
      _context = context;
      _plotSize = {
        width: _plot.offsetWidth,
        height: _plot.offsetHeight
      };
    }
    function _onStateUpdate(state) {
      _state = state;
      const { datasets } = _data;
      const range = {
        from: state.labelFromIndex,
        to: state.labelToIndex
      };
      const boundsAndParams = {
        begin: state.begin,
        end: state.end,
        totalXWidth: state.totalXWidth,
        yMin: state.yMinViewport,
        yMax: state.yMaxViewport,
        availableWidth: _plotSize.width,
        availableHeight: _plotSize.height - X_AXIS_HEIGHT,
        xPadding: GUTTER,
        yPadding: PLOT_TOP_PADDING
      };
      const visibilities = datasets.map(({ key }) => state[`opacity#${key}`]);
      const points = preparePoints(_data, datasets, range, visibilities, boundsAndParams);
      const projection = createProjection(boundsAndParams);
      let secondaryPoints = null;
      let secondaryProjection = null;
      if (_data.hasSecondYAxis) {
        const secondaryDataset = datasets.find((d) => d.hasOwnYAxis);
        const bounds = {
          yMin: state.yMinViewportSecond,
          yMax: state.yMaxViewportSecond
        };
        secondaryPoints = preparePoints(_data, [secondaryDataset], range, visibilities, bounds)[0];
        secondaryProjection = projection.copy(bounds);
      }
      if (!_data.hideCaption) {
        _header.setCaption(_getCaption(state));
      }
      clearCanvas(_plot, _context);
      const totalPoints = points.reduce((a, p) => a + p.length, 0);
      const simplification = getSimplificationDelta(totalPoints) * SIMPLIFIER_PLOT_FACTOR;
      drawDatasets(
        _context,
        state,
        _data,
        range,
        points,
        projection,
        secondaryPoints,
        secondaryProjection,
        PLOT_LINE_WIDTH,
        visibilities,
        _colors,
        false,
        simplification
      );
      if (!_data.isPie) {
        _axes.drawYAxis(state, projection, secondaryProjection);
        _axes.drawXAxis(state, projection);
      }
      _minimap.update(state);
      _tooltip.update(state, points, projection, secondaryPoints, secondaryProjection);
    }
    function _onRangeChange(range) {
      _stateManager.update({ range });
    }
    function _onFilterChange(filter) {
      _stateManager.update({ filter });
    }
    function _onFocus(focusOn) {
      if (_data.isBars || _data.isPie || _data.isSteps) {
        _stateManager.update({ focusOn });
      }
    }
    function _onZoomIn(labelIndex) {
      _zoomer.zoomIn(_state, labelIndex);
    }
    function _onZoomOut() {
      _zoomer.zoomOut(_state);
    }
    function _setupGlobalListeners() {
      new MutationObserver(() => {
        _stateManager.update();
      }).observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
      window.addEventListener("resize", () => {
        if (window.innerWidth !== _windowWidth) {
          _windowWidth = window.innerWidth;
          _redrawDebounced();
        }
      });
      window.addEventListener("orientationchange", () => {
        _redrawDebounced();
      });
    }
    function _redraw() {
      Object.assign(_data, analyzeData(originalData));
      _element.remove();
      _setupComponents();
    }
    function _getCaption(state) {
      let startIndex;
      let endIndex;
      if (_zoomer && _zoomer.isZoomed()) {
        startIndex = state.labelFromIndex === 0 ? 0 : state.labelFromIndex + 1;
        endIndex = state.labelToIndex === state.totalXWidth - 1 ? state.labelToIndex : state.labelToIndex - 1;
      } else {
        startIndex = state.labelFromIndex;
        endIndex = state.labelToIndex;
      }
      return isDataRange(_data.xLabels[startIndex], _data.xLabels[endIndex]) ? `${getLabelDate(_data.xLabels[startIndex])} — ${getLabelDate(_data.xLabels[endIndex])}` : getFullLabelDate(_data.xLabels[startIndex]);
    }
  }
  exports.create = create;
  Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
  return exports;
}({});

export default LovelyChart;
