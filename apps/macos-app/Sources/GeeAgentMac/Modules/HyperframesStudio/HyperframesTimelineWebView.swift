import SwiftUI
import WebKit

struct HyperframesTimelineWebView: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else {
            return
        }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !Self.isCancelledNavigation(error) else {
                return
            }
            webView.loadHTMLString(Self.failureHTML(error.localizedDescription), baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !Self.isCancelledNavigation(error) else {
                return
            }
            webView.loadHTMLString(Self.failureHTML(error.localizedDescription), baseURL: nil)
        }

        private static func isCancelledNavigation(_ error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        }

        private static func failureHTML(_ message: String) -> String {
            let escaped = message
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return """
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <style>
                body {
                  margin: 0;
                  min-height: 100vh;
                  display: grid;
                  place-items: center;
                  background: #101216;
                  color: rgba(255,255,255,0.78);
                  font: 13px -apple-system, BlinkMacSystemFont, sans-serif;
                }
                main {
                  width: min(460px, calc(100vw - 48px));
                  padding: 18px;
                  border: 1px solid rgba(255,255,255,0.12);
                  border-radius: 10px;
                  background: rgba(255,255,255,0.055);
                }
                h1 {
                  margin: 0 0 8px;
                  font-size: 15px;
                  font-weight: 650;
                }
                p {
                  margin: 0;
                  color: rgba(255,255,255,0.54);
                  line-height: 1.45;
                }
              </style>
            </head>
            <body>
              <main>
                <h1>Timeline failed to load</h1>
                <p>\(escaped)</p>
              </main>
            </body>
            </html>
            """
        }
    }
}
