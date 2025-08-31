package org.mytonwallet.plugins.air_app_launcher.airLauncher;

import android.graphics.Bitmap;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.UnsupportedEncodingException;

class CapacitorGlobalStorageWebViewClient extends WebViewClient {
  private final WebViewClientDelegate delegate;

  CapacitorGlobalStorageWebViewClient(WebViewClientDelegate delegate) {
    this.delegate = delegate;
  }

  @Override
  public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
    String emptyHTML = "<html><body></body></html>";
    try {
      InputStream dataStream = new ByteArrayInputStream(emptyHTML.getBytes("UTF-8"));
      return new WebResourceResponse(
        "text/html",
        "UTF-8",
        dataStream
      );
    } catch (UnsupportedEncodingException e) {
      e.printStackTrace();
      // Return null if there is an error, which means the request will proceed as usual
      return null;
    }
  }

  @Override
  public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
    return super.shouldOverrideUrlLoading(view, request);
  }

  @Deprecated
  @Override
  public boolean shouldOverrideUrlLoading(WebView view, String url) {
    return super.shouldOverrideUrlLoading(view, url);
  }

  @Override
  public void onPageFinished(WebView view, String url) {
    super.onPageFinished(view, url);
    if (delegate != null) {
      delegate.onPageFinished();
    }
  }

  @Override
  public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
    super.onReceivedError(view, request, error);
  }

  @Override
  public void onPageStarted(WebView view, String url, Bitmap favicon) {
    super.onPageStarted(view, url, favicon);
  }

  @Override
  public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
    super.onReceivedHttpError(view, request, errorResponse);
  }

  @Override
  public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
    return super.onRenderProcessGone(view, detail);
  }

  interface WebViewClientDelegate {
    void onPageFinished();
  }
}
