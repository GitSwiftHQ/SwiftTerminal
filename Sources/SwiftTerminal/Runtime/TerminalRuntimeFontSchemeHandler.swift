import Foundation
import WebKit

final class TerminalRuntimeFontSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "swiftterminalfont"

    private struct Resource {
        let data: Data
        let mimeType: String
    }

    private let queue = DispatchQueue(label: "swiftterminal.runtime.font.scheme")
    private var resources: [String: Resource] = [:]
    private var tokensByFont: [TerminalCustomFont: String] = [:]

    func register(_ font: TerminalCustomFont) -> URL {
        let token = queue.sync {
            if let existingToken = tokensByFont[font] {
                return existingToken
            }

            let token = UUID().uuidString
            resources[token] = Resource(
                data: font.data,
                mimeType: font.format.mimeType
            )
            tokensByFont[font] = token
            return token
        }

        return URL(string: "\(Self.scheme)://font/\(token)")!
    }

    func webView(_: WKWebView, start task: any WKURLSchemeTask) {
        guard
            let url = task.request.url,
            url.host == "font",
            let token = url.pathComponents.last
        else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }

        let resource = queue.sync {
            resources[token]
        }

        guard let resource else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": resource.mimeType,
                "Access-Control-Allow-Origin": "*",
            ]
        )!
        task.didReceive(response)
        task.didReceive(resource.data)
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
