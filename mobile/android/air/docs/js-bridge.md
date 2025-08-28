# JS Bridge

To reuse our stable blockchain logic from the web app and legacy mobile applications,
we bundle the necessary JS code into a minified file using Webpack.

The initial proposal for this approach can be found in our [2024 MyTonWallet iOS app contest](https://t.me/MyTonWalletEn/47).

The `JSWebViewBridge` file is responsible for communication between the SDK and the native app layer.
It creates an invisible WebView and injects the SDK code to run in the web environment.

API methods are called using the `callApi` method, and once the promise is resolved (or rejected), the response callback is triggered.

All events from the SDK are received and handled in the `onUpdate` method.

We have also overridden some methods to allow the SDK controlled access to `Secure Storage` and `Ledger` devices. These methods are referred to as `nativeCall`.
