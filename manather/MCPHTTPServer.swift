//
//  MCPHTTPServer.swift
//  manather
//
//  A tiny, dependency-free HTTP/1.1 server bound to loopback (127.0.0.1). It does
//  exactly three things: accept a local connection, parse one request, and hand
//  the body to a handler. No third-party packages — just Network.framework, in
//  keeping with the project's "pure Apple frameworks" rule.
//
//  Security: it only ever binds to 127.0.0.1 (never a public interface) and every
//  request to /mcp must carry the right `Authorization: Bearer <token>` header.
//  The MCP protocol itself lives one layer up (see MCPServer); this file is pure
//  transport + auth.
//

import Foundation
import Network

/// Loopback HTTP transport for the MCP endpoint. Marked `@unchecked Sendable`
/// because all mutable state is confined to `queue`.
final class MCPHTTPServer: @unchecked Sendable {

    // MARK: - Request / response value types

    // These are pure transport value types, built and read on the background
    // networking queue, so they must stay off the main actor (the project
    // defaults declarations to @MainActor).
    nonisolated struct HTTPRequest: Sendable {
        let method: String
        let path: String
        /// Header names are lowercased for case-insensitive lookup.
        let headers: [String: String]
        let body: Data
    }

    nonisolated struct HTTPResponse: Sendable {
        var status: Int
        var headers: [String: String]
        var body: Data

        static func json(_ data: Data, status: Int = 200) -> HTTPResponse {
            HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: data)
        }
        static func text(_ string: String, status: Int) -> HTTPResponse {
            HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"],
                         body: Data(string.utf8))
        }
    }

    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    // MARK: - State (touched only on `queue`)

    let port: UInt16
    private let token: String
    private let queue = DispatchQueue(label: "com.manather.mcp.http")
    private var listener: NWListener?
    private var handler: Handler = { _ in .text("Not configured", status: 503) }
    private var onStatus: (@Sendable (Bool, String?) -> Void)?
    private(set) var isRunning = false

    init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    // MARK: - Lifecycle

    /// Starts listening on 127.0.0.1:port. Throws if the listener can't be created.
    /// `onStatus(running, error)` reports the real bind result asynchronously
    /// (the actual socket bind happens after this returns).
    func start(handler: @escaping Handler,
               onStatus: @escaping @Sendable (Bool, String?) -> Void) throws {
        try queue.sync {
            guard !isRunning else { return }
            self.handler = handler
            self.onStatus = onStatus

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw NSError(domain: "MCPHTTPServer", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
            }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Bind to loopback only — never reachable from another machine. The
            // port comes from this endpoint, so we don't also pass `on:`.
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)

            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.onStatus?(true, nil)
                case .failed(let error):
                    self?.isRunning = false
                    self?.onStatus?(false, "\(error)")
                case .waiting(let error):
                    self?.onStatus?(false, "waiting: \(error)")
                case .cancelled:
                    self?.onStatus?(false, nil)
                default:
                    break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
            isRunning = true
        }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            isRunning = false
        }
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    /// Reads until the full request (head + Content-Length body) has arrived.
    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buffer = buffer
            if let data, !data.isEmpty { buffer.append(data) }

            if let parsed = self.parse(buffer) {
                self.dispatch(parsed, on: conn)
                return
            }
            if error != nil || isComplete {
                self.send(.text("Bad Request", status: 400), on: conn)
                return
            }
            // Need more bytes.
            self.receive(conn, buffer: buffer)
        }
    }

    /// Parses a complete HTTP request from `buffer`, or nil if more bytes are needed.
    private func parse(_ buffer: Data) -> HTTPRequest? {
        // Find the CRLFCRLF that ends the header block.
        let separator = Data([13, 10, 13, 10])
        guard let range = buffer.range(of: separator) else { return nil }

        let headData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
        guard let headString = String(data: headData, encoding: .utf8) else { return nil }

        var lines = headString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        lines.removeFirst()

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }
        let method = String(requestParts[0])
        let path = String(requestParts[1])

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = range.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        if available < contentLength { return nil }   // wait for the rest of the body

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = buffer.subdata(in: bodyStart..<bodyEnd)
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    /// Routes a parsed request: auth-checks /mcp, then runs the handler.
    private func dispatch(_ request: HTTPRequest, on conn: NWConnection) {
        // Only the MCP route exists.
        let routePath = request.path.split(separator: "?").first.map(String.init) ?? request.path
        guard routePath == "/mcp" else {
            send(.text("Not Found", status: 404), on: conn)
            return
        }
        guard request.method.uppercased() == "POST" else {
            send(.text("Method Not Allowed", status: 405), on: conn)
            return
        }
        guard authorized(request) else {
            send(.text("Unauthorized", status: 401), on: conn)
            return
        }

        let handler = self.handler
        Task {
            let response = await handler(request)
            self.send(response, on: conn)
        }
    }

    private func authorized(_ request: HTTPRequest) -> Bool {
        guard let auth = request.headers["authorization"] else { return false }
        let expected = "bearer \(token)".lowercased()
        return auth.lowercased() == expected
    }

    // MARK: - Response writing

    private func send(_ response: HTTPResponse, on conn: NWConnection) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"

        var out = Data(head.utf8)
        out.append(response.body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default:  return "Status"
        }
    }
}
