package org.mytonwallet.app_air.uiinappbrowser.helpers

import android.webkit.WebView

object IABDarkModeStyleHelpers {
    private const val CSS = """
body {
    background-color: #fff;
}
.tl_article .tl_article_content,
.tl_article .tl_article_content .ql-editor *,
.tl_article h1,
.tl_article h2 {
    color: #000;
}
.tl_article_header address,
.tl_article_header address a {
    color: #8E8E93;
}
@media (prefers-color-scheme: dark) {
    body {
        background-color: #0E0E0F;
    }
    .tl_article .tl_article_content,
    .tl_article .tl_article_content .ql-editor *,
    .tl_article h1,
    .tl_article h2 {
        color: #fff;
    }
    .tl_article_header address,
    .tl_article_header address a {
        color: #8E8E93;
    }
}
"""

    private const val INJECT_SCRIPT = """
var style = document.createElement('style');
style.innerHTML = `$CSS`;
document.head.appendChild(style);
"""

    fun applyOn(webView: WebView) {
        webView.evaluateJavascript(INJECT_SCRIPT, null)
    }
}
