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

## Notes

- This does not try to preserve Telegram compatibility.
- The extracted UI no longer depends on `AsyncDisplayKit`, `Display`, `AppBundle`, `SwiftSignalKit`, or `TelegramPresentationData`.
- The sample portfolio adapter currently selects the dominant assets by impact and folds the remainder into `Other`.
