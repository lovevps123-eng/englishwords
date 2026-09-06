import SwiftUI
import WebKit

enum TurnstileBridgeValidationError: Error {
    case httpsOriginRequired
}

struct TurnstileBridgeValidator {
    static let handlerName = "turnstile"
    static let maximumTokenLength = 4_096

    let challengeURL: URL
    private let expectedOrigin: URL

    init(expectedBaseURL: URL) throws {
        guard expectedBaseURL.scheme?.lowercased() == "https",
              expectedBaseURL.host != nil else {
            throw TurnstileBridgeValidationError.httpsOriginRequired
        }
        expectedOrigin = expectedBaseURL
        challengeURL = expectedBaseURL.appendingPathComponent("app-turnstile")
    }

    func isAllowedNavigation(to url: URL?, isMainFrame: Bool) -> Bool {
        guard isMainFrame else { return true }
        return url == challengeURL
    }

    func token(
        handlerName: String,
        sourceURL: URL?,
        isMainFrame: Bool,
        body: Any
    ) -> String? {
        guard handlerName == Self.handlerName,
              isMainFrame,
              let sourceURL,
              hasSameOrigin(sourceURL, as: expectedOrigin),
              let payload = body as? [String: Any],
              payload.count == 2,
              payload["type"] as? String == "turnstile-token",
              let token = payload["token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              token.utf8.count <= Self.maximumTokenLength else {
            return nil
        }
        return token
    }

    private func hasSameOrigin(_ url: URL, as expected: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return url.scheme?.lowercased() == expected.scheme?.lowercased()
            && url.host?.lowercased() == expected.host?.lowercased()
            && effectivePort(of: url) == effectivePort(of: expected)
    }

    private func effectivePort(of url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
    }
}

struct TurnstileChallengeView: UIViewRepresentable {
    private let validator: TurnstileBridgeValidator?
    private let onToken: (String) -> Void
    private let onFailure: (String) -> Void

    init(
        configuration: AppConfiguration = AppConfiguration(),
        onToken: @escaping (String) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        validator = try? TurnstileBridgeValidator(expectedBaseURL: configuration.baseURL)
        self.onToken = onToken
        self.onFailure = onFailure
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(validator: validator, onToken: onToken, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: TurnstileBridgeValidator.handlerName)

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = context.coordinator
        if let challengeURL = validator?.challengeURL {
            webView.load(URLRequest(url: challengeURL))
        } else {
            DispatchQueue.main.async {
                onFailure("验证页面必须使用 HTTPS")
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: TurnstileBridgeValidator.handlerName
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let validator: TurnstileBridgeValidator?
        private let onToken: (String) -> Void
        private let onFailure: (String) -> Void

        init(
            validator: TurnstileBridgeValidator?,
            onToken: @escaping (String) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.validator = validator
            self.onToken = onToken
            self.onFailure = onFailure
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let token = validator?.token(
                handlerName: message.name,
                sourceURL: message.frameInfo.request.url,
                isMainFrame: message.frameInfo.isMainFrame,
                body: message.body
            ) else { return }
            onToken(token)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            let allowed = validator?.isAllowedNavigation(
                to: navigationAction.request.url,
                isMainFrame: isMainFrame
            ) ?? false
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onFailure("验证页面加载失败，请重试")
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            onFailure("验证页面加载失败，请重试")
        }
    }
}
