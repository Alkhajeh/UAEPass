import WebKit

// webview_flutter_wkwebview forwards HTTP status without the response's frame.
// Observe that flag here and forward all other decisions to its delegate.
final class MainFrameHttpErrorObserver: NSObject, WKNavigationDelegate {
  private weak var webView: WKWebView?
  private let delegate: WKNavigationDelegate?
  private let onError: () -> Void

  init(webView: WKWebView, onError: @escaping () -> Void) {
    self.webView = webView
    self.delegate = webView.navigationDelegate
    self.onError = onError
    super.init()
    webView.navigationDelegate = self
  }

  func detach() {
    guard let webView, webView.navigationDelegate === self else { return }
    webView.navigationDelegate = delegate
  }

  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || (delegate?.responds(to: selector) ?? false)
  }

  override func forwardingTarget(for selector: Selector!) -> Any? {
    if delegate?.responds(to: selector) == true { return delegate }
    return super.forwardingTarget(for: selector)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if navigationResponse.isForMainFrame,
      let response = navigationResponse.response as? HTTPURLResponse,
      (400..<600).contains(response.statusCode)
    {
      onError()
      decisionHandler(.cancel)
      return
    }
    if delegate?.webView?(
      webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler) == nil
    {
      decisionHandler(.allow)
    }
  }
}
