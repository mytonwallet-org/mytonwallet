(() => {
  const TG_SQUARE_BTN_HTML = `<div><img src="https://wallet.tg/images/logo-288.png" alt="" draggable="false"></div><div><div fontsize="14px" fontweight="510" lineheight="130%" color="#0F0F0F" data-tc-text="true">Wallet On</div></div><div fontsize="14px" fontweight="510" lineheight="130%" color="#0F0F0F" data-tc-text="true">Telegram</div>`;
  const TG_BADGE_FILENAME = 'tg.png';
  const TG_BADGE_STYLE = 'position: absolute; right: 10px; top: 50px; width: 24px; height: 24px; border-radius: 6px; box-shadow: 0 2px 8px 0 rgba(0, 0, 0, 0.08);';

  const MTW_ICON = '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" fill="none" viewBox="0 0 28 28"><g clip-path="url(#a)"><rect width="28" height="28" fill="url(#b)" rx="13.672"/><path fill="#fff" fill-opacity=".85" d="M8.27 9.885c-.389.18-.583.27-.721.382-.431.35-.619.92-.48 1.458.044.173.147.36.353.735l2.299 4.194 1.884 3.437c.156.286.24.438.332.548l.002.003.018.02c.312.349.786.505 1.244.41.148-.03.306-.104.623-.25.388-.18.582-.27.72-.382.432-.35.62-.92.481-1.458-.044-.173-.147-.36-.353-.735l-2.299-4.194-1.884-3.437c-.157-.285-.24-.437-.332-.548l-.002-.002-.018-.02a1.31 1.31 0 0 0-1.244-.41c-.148.03-.306.103-.623.25M14.176 7.179c-.389.18-.583.269-.721.381-.431.35-.619.92-.48 1.458.044.173.147.36.353.736l2.299 4.193 1.884 3.437c.157.286.24.438.332.549l.003.002.017.02c.312.349.786.505 1.244.41.148-.03.306-.104.623-.25.388-.18.582-.27.72-.382.432-.35.62-.92.481-1.458-.044-.173-.147-.36-.353-.735l-2.299-4.194-1.884-3.436c-.157-.286-.24-.438-.332-.549l-.002-.001-.018-.022a1.31 1.31 0 0 0-1.244-.41c-.148.03-.306.104-.623.25"/><g fill="#fff" filter="url(#c)"><path fill-rule="evenodd" d="m10.155 10.066-.002-.002zm-.147-.084Z" clip-rule="evenodd"/><path d="M6.467 28H9.72V10.225a.246.246 0 0 1 .287-.243l.037.01q.065.021.108.072l-.016-.019a1.31 1.31 0 0 0-1.244-.41c-.148.03-.306.104-.623.25l-.09.042-.068.031c-.362.168-.543.251-.695.355-.488.335-.82.854-.92 1.439-.03.181-.03.38-.03.779z"/></g><g fill="#fff" filter="url(#d)"><path fill-rule="evenodd" d="M15.958 7.287q.061.023.103.073l-.002-.003a.25.25 0 0 0-.101-.07" clip-rule="evenodd"/><path d="M15.627 18.176V7.518a.246.246 0 0 1 .287-.243.3.3 0 0 1 .044.012q.06.023.1.07l-.015-.019a1.31 1.31 0 0 0-1.244-.41c-.148.03-.306.104-.623.25l-.038.018-.12.055c-.362.168-.543.251-.695.355-.488.335-.82.854-.92 1.439-.03.181-.03.38-.03.779v10.658a.246.246 0 0 1-.434.16l.018.02c.312.349.786.505 1.244.41.148-.03.306-.104.623-.25l.152-.07.005-.003h.001c.362-.168.542-.251.694-.355.49-.335.821-.854.92-1.439.03-.181.03-.38.03-.779"/></g><g filter="url(#e)"><path fill="#fff" d="M21.533 15.47V0H18.28v17.775a.246.246 0 0 1-.434.16l.018.02c.312.349.786.505 1.244.41.148-.03.306-.104.623-.25l.13-.06.028-.014c.362-.167.543-.25.695-.354.488-.335.82-.854.92-1.439.03-.181.03-.38.03-.779"/></g></g><defs><filter id="c" width="6.313" height="21.017" x="5.592" y="8.405" color-interpolation-filters="sRGB" filterUnits="userSpaceOnUse"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feColorMatrix in="SourceAlpha" result="hardAlpha" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"/><feOffset dx=".438" dy=".109"/><feGaussianBlur stdDeviation=".656"/><feComposite in2="hardAlpha" operator="out"/><feColorMatrix values="0 0 0 0 0 0 0 0 0 0.403922 0 0 0 0 0.976471 0 0 0 0.3 0"/><feBlend in2="BackgroundImageFix" result="effect1_dropShadow_3197_2"/><feBlend in="SourceGraphic" in2="effect1_dropShadow_3197_2" result="shape"/></filter><filter id="d" width="6.747" height="16.823" x="11.064" y="5.698" color-interpolation-filters="sRGB" filterUnits="userSpaceOnUse"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feColorMatrix in="SourceAlpha" result="hardAlpha" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"/><feOffset dx=".438" dy=".109"/><feGaussianBlur stdDeviation=".656"/><feComposite in2="hardAlpha" operator="out"/><feColorMatrix values="0 0 0 0 0 0 0 0 0 0.403922 0 0 0 0 0.976471 0 0 0 0.3 0"/><feBlend in2="BackgroundImageFix" result="effect1_dropShadow_3197_2"/><feBlend in="SourceGraphic" in2="effect1_dropShadow_3197_2" result="shape"/></filter><filter id="e" width="6.313" height="21.017" x="16.97" y="-1.203" color-interpolation-filters="sRGB" filterUnits="userSpaceOnUse"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feColorMatrix in="SourceAlpha" result="hardAlpha" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"/><feOffset dx=".438" dy=".109"/><feGaussianBlur stdDeviation=".656"/><feComposite in2="hardAlpha" operator="out"/><feColorMatrix values="0 0 0 0 0 0 0 0 0 0.403922 0 0 0 0 0.976471 0 0 0 0.3 0"/><feBlend in2="BackgroundImageFix" result="effect1_dropShadow_3197_2"/><feBlend in="SourceGraphic" in2="effect1_dropShadow_3197_2" result="shape"/></filter><linearGradient id="b" x1="14" x2="14" y1="0" y2="28" gradientUnits="userSpaceOnUse"><stop stop-color="#00b7ff"/><stop offset="1" stop-color="#0067f9"/></linearGradient><clipPath id="a"><rect width="28" height="28" fill="#fff" rx="13.672"/></clipPath></defs></svg>';
  const MTW_LARGE_BTN_MOBILE_HTML = `${MTW_ICON} My Wallet<div></div>`;

  let isObservingTcWidget = false;

  init();

  function init() {
    const tcWidget = document.getElementById('tc-widget-root');

    if (tcWidget) {
      patchAndObserveTcWidget(tcWidget);
    } else if (document.body) {
      observeBody();
    } else {
      document.addEventListener('DOMContentLoaded', init);
    }
  }

  function observeBody() {
    const bodyObserver = new MutationObserver(() => {
      const tcWidget = document.getElementById('tc-widget-root');

      if (tcWidget) {
        bodyObserver.disconnect();
        patchAndObserveTcWidget(tcWidget);
      }
    });

    bodyObserver.observe(document.body, { childList: true });
  }

  function patchAndObserveTcWidget(tcWidget) {
    if (isObservingTcWidget) return;

    isObservingTcWidget = true;

    let universalContainer = document.querySelector('[data-tc-wallets-modal-universal-mobile=true], [data-tc-wallets-modal-universal-desktop=true]');
    if (universalContainer) {
      applyFriendlyPatch(universalContainer);
    }

    new MutationObserver(() => {
      const newUniversalContainer = document.querySelector('[data-tc-wallets-modal-universal-mobile=true], [data-tc-wallets-modal-universal-desktop=true]');

      if (newUniversalContainer !== universalContainer) {
        universalContainer = newUniversalContainer;

        if (newUniversalContainer) {
          applyFriendlyPatch(newUniversalContainer);
        }
      }
    })
      .observe(tcWidget, {
        subtree: true,
        childList: true,
      });
  }

  function applyFriendlyPatch(container) {
    const ul = container.querySelector('ul');
    if (!ul) return;
    const mwLi = Array.from(ul.children).find((i) => i.textContent.startsWith('My Wallet'));
    if (!mwLi) return;

    const isDesktop = Boolean(container.getAttribute('data-tc-wallets-modal-universal-desktop'));
    if (isDesktop) {
      if (ul.firstElementChild !== mwLi) {
        ul.insertBefore(mwLi, ul.firstElementChild);
      }
    } else {
      const mwBtn = mwLi.firstElementChild;

      const tgBtn = container.querySelector('[data-tc-button=true]');
      const tgBtnOldClassName = tgBtn.className;
      tgBtn.className = mwBtn.className;
      tgBtn.innerHTML = TG_SQUARE_BTN_HTML;
      tgBtn.firstElementChild.className = mwBtn.firstElementChild.className;
      applyImgClassName(tgBtn, ul);
      applyBadgeStyle(tgBtn);
      const textClassName = mwBtn.querySelector('[data-tc-text]').className;
      Array.from(tgBtn.querySelectorAll('[data-tc-text]')).forEach((el) => {
        el.className = textClassName;
      });

      mwBtn.className = tgBtnOldClassName;
      const themeTextColor = getComputedStyle(container.parentNode.parentNode).color;
      const isDarkTheme = Number(themeTextColor.match(/\d+/)?.[0] ?? 0) >= 128;
      mwBtn.style.color = isDarkTheme ? '#FFFFFF' : '#0F0F0F';
      mwBtn.style.backgroundColor = isDarkTheme ? '#1C1E24' : '#EDEFF4';
      mwBtn.style.justifyContent = 'center';
      mwBtn.style.fontWeight = '600';
      mwBtn.style.fontSize = '16px';
      mwBtn.innerHTML = MTW_LARGE_BTN_MOBILE_HTML;
      tgBtn.parentNode.insertBefore(mwBtn, tgBtn);
      mwLi.remove();

      const subtitleEl = mwBtn.previousSibling;
      subtitleEl.innerHTML = subtitleEl.innerHTML.replace('Wallet in Telegram', '<b>My Wallet</b>');

      const listHeadingEl = ul.previousElementSibling;
      if (listHeadingEl && listHeadingEl.textContent.includes('Choose other application')) {
        listHeadingEl.textContent = 'Other applications';
      }

      const newLi = document.createElement('li');
      newLi.appendChild(tgBtn);
      ul.prepend(newLi);
    }
  }

  function applyImgClassName(tgBtn, ul) {
    const nonMwLi = Array.from(ul.children).find((i) => !i.textContent.startsWith('My Wallet'));
    if (!nonMwLi) return;
    let img = nonMwLi.querySelector('img');

    if (img) {
      tgBtn.querySelector('img').className = img.className;
    } else {
      const liObserver = new MutationObserver(() => {
        img = nonMwLi.querySelector('img');

        if (img) {
          liObserver.disconnect();
          tgBtn.querySelector('img').className = img.className;
        }
      });

      liObserver.observe(nonMwLi, {
        childList: true,
        subtree: true,
      });
    }
  }

  function applyBadgeStyle(tgBtn) {
    let tgBadge = Array.from(tgBtn.querySelectorAll('img'))
      .find((img) => img.src.endsWith(TG_BADGE_FILENAME));

    if (tgBadge) {
      tgBadge.style.cssText = TG_BADGE_STYLE;
    } else {
      const btnObserver = new MutationObserver(() => {
        tgBadge = Array.from(tgBtn.querySelectorAll('img'))
          .find((img) => img.src.endsWith(TG_BADGE_FILENAME));

        if (tgBadge) {
          btnObserver.disconnect();
          tgBadge.style.cssText = TG_BADGE_STYLE;
        }
      });

      btnObserver.observe(tgBtn, {
        childList: true,
        subtree: true,
      });
    }
  }
})();
