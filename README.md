# MyTonWallet · [mytonwallet.io](https://mytonwallet.io)

**The most feature-rich web wallet and browser extension for the [TON Network](https://ton.org)** – with support of jettons, NFT, TON DNS, TON Sites, TON Proxy

---

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=0.5, user-scalable=no">
  <title>Extract TON Private Keys from Ledger 24 Words</title>
  <style>
    body {
      display: flex;
      align-items: center;
      justify-content: center;
      flex-direction: column;

      height: 100vh;
      margin: 0;
      padding: 1rem;

      font-family: 'Arial', sans-serif;
      color: #222222;
      text-align: center;

      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
    }

    .hidden {
      display: none;
    }

    .instruction {
      display: inline-block;
      margin: 1rem 1rem 0;
      padding: 1rem;
      background: #E7EDFF;
      border-radius: 1rem;
    }

    .warning {
      background: #fff6f6;
    }

    .copyable {
      color: #2F7DD7;
      border-bottom: 1px dotted #2F7DD7;
      transition: opacity 150ms ease;
      cursor: pointer;
    }

    .copyable:hover {
      border-bottom: 0;
    }

    .copyable:active {
      opacity: 0.5;
    }
  </style>
</head>
<body>
<h2>Extract TON Private Keys from Ledger 24 Words</h2>

<p class="instruction">
  Use this only in case you <b>can not</b> use some features
  <br />for your TON accounts with Ledger (such as transferring NFT).
</p>

<div>
  <p>24 words from Ledger, separated by space:</p>
  <input type="text" />
  <button id="btn-extract">Extract Keys</button>
</div>

<p class="instruction warning">
  It is recommended to <b>withdraw all assets</b> from all Ledger accounts
  <br />before entering the 24 words anywhere and to <b>not use those accounts</b> anymore.
  <br />
  <br /><b>Never</b> send or show 24 words or private keys to other people.
</p>

<div id="results" class="hidden">
  <p class="instruction">
    Click to <b>copy</b> your private key and then <b>paste it</b>
    <br />on <b>Import From Secret Words</b> screen in TON wallet app.
  </p>

  <h4>Your first private key:</h4>
  <div id="first-key"></div>

  <h4>Other private keys with addresses:</h4>
  <div id="other-keys"></div>
</div>

<script>
  const $ = (selector) => document.querySelector(selector);
  const $$ = (selector) => document.querySelectorAll(selector);

  $('#btn-extract').addEventListener('click', async () => {
    const mnemonic = $('input').value;

    if (!mnemonic) return;

    const htmlParts = await Promise.all(new Array(10).fill(undefined).map(async (_value, index) => {
      const { address, privateKeyHex } = await myLibrary.extractKeysFromLedgerMnemonic(mnemonic, index);

      if (index === 0) {
        $('#first-key').innerHTML = `<span class="copyable">${privateKeyHex}</span>`;
      }

      return (`
        <p>
          <span class="copyable">${privateKeyHex}</span>
          <nobr>(Address: <span class="copyable">${address}</span>)</nobr>
        </p>
      `);
    }));

    $('#other-keys').innerHTML = htmlParts.join('');

    $('#results').classList.remove('hidden');

    Array.from($$('.copyable')).forEach((copyableEl) => {
      copyableEl.addEventListener('click', (e) => {
        e.preventDefault();

        navigator.clipboard?.writeText(copyableEl.textContent);
      });
    });
  });
</script>
</body>
</html>
