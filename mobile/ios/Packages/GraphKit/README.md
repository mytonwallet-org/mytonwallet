# GraphKit

Small extraction workspace for Telegram chart components, packaged as a single Swift package with an example app.

## Structure

- `Sources/GraphKit/GraphCore`: copied chart renderers, models, and controllers.
- `Sources/GraphKit/GraphUI`: UIKit hosting and interaction views extracted from Telegram.
- `Examples/PortfolioDemoApp`: example iOS app wired to the local `GraphKit` package, including the sample portfolio adapter and demo composition screen.

## Current Goal

The first extracted flow targets Telegram's languages chart behavior:

- initial pie view
- zoom out to historical stacked percentage area
- reusable chart code kept largely intact inside one package target

## Candlesticks

Use `CandlestickChartData(candles:interval:)` with ascending OHLC candles and an explicit period in seconds. Each candle's `date` is the period start. The throwing initializer validates finite prices, high/low bounds, and non-overlapping periods; missing periods remain gaps. Empty and single-candle series are supported.

```swift
let data = try CandlestickChartData(candles: [
    Candlestick(date: date, open: 3.20, high: 3.35, low: 3.15, close: 3.30),
], interval: 3600)
let controller = CandlestickChartController(data: data)
chartView.setup(controller: controller, noInitialZoom: true)
```

`CandlestickChartController` uses the existing `ChartContainerView` range selector, theme, and selection popover. Rising/falling colors are configurable, and `detailsValueTextProvider` formats OHLC values (IDs: `open`, `high`, `low`, `close`). Values are kept in OHLC order. The visible price axis includes the full high/low range.

VoiceOver treats the plot as an adjustable element. Swipe up or down to move between visible candles and hear the date and OHLC values. Price padding scales with the data; ranges that cannot be represented with finite bounds and a positive finite span are left unrendered.

Run the **MyLab** scheme, then open **Charts → Candlesticks**. The `mywallet-ui://show/charts/candlesticks?variant=market` route opens the deterministic mock market; `gaps`, `flat`, `single`, and `empty` variants exercise edge cases. These fixtures do not call the backend. `GraphKitTests` runs through the workspace's `AirTests` plan.

## Extraction notes

- This does not try to preserve Telegram compatibility.
- The extracted UI no longer depends on `AsyncDisplayKit`, `Display`, `AppBundle`, `SwiftSignalKit`, or `TelegramPresentationData`.
- The sample portfolio adapter currently selects the dominant assets by impact and folds the remainder into `Other`.
