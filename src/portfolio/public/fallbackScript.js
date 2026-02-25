var APP_RENDERED_TIMEOUT = 5000;

function checkAppRendered() {
  if (document.documentElement.className.indexOf('is-rendered') !== -1) return;

  var messageEl = document.createElement('div');
  messageEl.className = 'browser-update-message';

  var text = 'It looks like your browser is outdated. \nTry to update it.';
  if (window.navigator.userAgent.includes('Android')) {
    text = 'It looks like your browser is outdated. \nPlease update Google Chrome and Android WebView apps.';
  }
  messageEl.textContent = text;

  document.body.appendChild(messageEl);
}

window.setTimeout(checkAppRendered, APP_RENDERED_TIMEOUT);
