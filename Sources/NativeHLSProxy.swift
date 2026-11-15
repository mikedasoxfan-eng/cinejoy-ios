import Foundation
import Network
import Darwin

/// Corrects the provider's image MIME without copying its stream resolver.
/// Each instance is restricted to its own tokenized, loopback-only listener.
@MainActor final class NativeHLSProxy {
    private var server: HLSLoopbackServer?

    func start(masterURL: URL) async throws -> URL {
        stop()
        let next = HLSLoopbackServer()
        server = next
        do { return try await next.start(masterURL: masterURL) }
        catch { next.stop(); if server === next { server = nil }; throw error }
    }

    func stop() { server?.stop(); server = nil }
    deinit { server?.stop() }
}

private final class HLSLoopbackServer: @unchecked Sendable {
    private struct Route: Sendable { let url: URL; let kind: HLSPlaylist.ResourceKind }
    private let queue = DispatchQueue(label: "local.cinejoy.hls-proxy")
    private let token = UUID().uuidString
    private var listener: NWListener?
    private var baseURL: URL?
    private var routes: [String: Route] = [:]
    private var routeKeys: [String: String] = [:]
    private var connections: [UUID: NWConnection] = [:]
    private var requests: [UUID: Task<Void, Never>] = [:]
    private var stopped = false
    private var starting: CheckedContinuation<URL, Error>?
    private let slots = HLSFetchSlots()

    func start(masterURL: URL) async throws -> URL {
        try await Self.validateDestination(masterURL)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !stopped else { continuation.resume(throwing: CancellationError()); return }
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters, on: .any)
                    self.listener = listener
                    starting = continuation
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            guard let port = self.listener?.port,
                                  let base = URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.token)/") else { return }
                            self.baseURL = base
                            do { self.finishStart(.success(try self.register(masterURL, kind: .playlist))) }
                            catch { self.finishStart(.failure(error)); self.close() }
                        case .failed(let error): self.finishStart(.failure(error)); self.close()
                        case .cancelled: self.finishStart(.failure(CancellationError()))
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    listener.start(queue: queue)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() { queue.async { [self] in close() } }

    private func finishStart(_ result: Result<URL, Error>) {
        let continuation = starting; starting = nil
        continuation?.resume(with: result)
    }

    private func close() {
        stopped = true
        finishStart(.failure(CancellationError()))
        listener?.cancel(); listener = nil
        for task in requests.values { task.cancel() }
        for connection in connections.values { connection.cancel() }
        requests.removeAll(); connections.removeAll(); routes.removeAll(); routeKeys.removeAll()
        baseURL = nil
    }

    private func register(_ url: URL, kind: HLSPlaylist.ResourceKind) throws -> URL {
        guard HLSPlaylist.isPermitted(url), let baseURL, routes.count < 40_000 else { throw URLError(.unsupportedURL) }
        let key = "\(kind):\(url.absoluteString)"
        if let path = routeKeys[key] { return baseURL.appendingPathComponent(path) }
        let path = UUID().uuidString + (kind == .playlist ? ".m3u8" : kind == .media ? ".mp4" : ".bin")
        routes[path] = Route(url: url, kind: kind); routeKeys[key] = path
        return baseURL.appendingPathComponent(path)
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped, connections.count < 12 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish(id) }
            if case .cancelled = state { self?.finish(id) }
        }
        connection.start(queue: queue)
        receive(connection, id: id, accumulated: Data())
        queue.asyncAfter(deadline: .now() + 45) { [weak self] in self?.finish(id) }
    }

    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else { return }
            var header = accumulated; header.append(data ?? Data())
            if header.count > 16_384 { self.respond(connection, id: id, status: 431); return }
            if let end = header.range(of: Data("\r\n\r\n".utf8)) {
                self.handle(header[..<end.lowerBound], connection: connection, id: id)
            } else if complete || error != nil { self.finish(id) }
            else { self.receive(connection, id: id, accumulated: header) }
        }
    }

    private func handle(_ data: Data.SubSequence, connection: NWConnection, id: UUID) {
        guard let text = String(data: Data(data), encoding: .utf8) else { respond(connection, id: id, status: 400); return }
        let lines = text.components(separatedBy: "\r\n")
        let request = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, ["GET", "HEAD"].contains(String(request[0])), request[2] == "HTTP/1.1" || request[2] == "HTTP/1.0" else {
            respond(connection, id: id, status: 405); return
        }
        let prefix = "/\(token)/"
        let path = String(request[1])
        guard path.hasPrefix(prefix), !path.contains("?"), !path.contains("%"),
              let route = routes[String(path.dropFirst(prefix.count))] else { respond(connection, id: id, status: 404); return }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { respond(connection, id: id, status: 400); return }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil,
              headers["content-length"] == nil || headers["content-length"] == "0" else { respond(connection, id: id, status: 400); return }
        if let range = headers["range"], !HLSPlaylist.validRange(range) { respond(connection, id: id, status: 416); return }
        let isHead = request[0] == "HEAD"
        let byteRange = route.kind == .playlist ? nil : headers["range"]
        let slots = self.slots
        requests[id] = Task { [weak self] in
            await slots.acquire()
            defer { Task { await slots.release() } }
            do {
                try Task.checkCancellation()
                try await Self.validateDestination(route.url)
                var request = URLRequest(url: route.url, timeoutInterval: 30)
                // Fetch the body for HEAD too: playlist rewriting changes its size.
                request.httpMethod = "GET"
                request.setValue("https://cinejoy.pk/", forHTTPHeaderField: "Referer")
                request.setValue("https://cinejoy.pk", forHTTPHeaderField: "Origin")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                if let byteRange { request.setValue(byteRange, forHTTPHeaderField: "Range") }
                let fetched = try await HLSBoundedFetch().fetch(request)
                try Task.checkCancellation()
                self?.queue.async { [weak self] in
                    guard let self, !self.stopped, self.connections[id] != nil else { return }
                    do {
                        guard [200, 206, 416].contains(fetched.response.statusCode) else { throw URLError(.badServerResponse) }
                        if fetched.response.statusCode == 416 {
                            self.respond(connection, id: id, status: 416, extra: self.rangeHeaders(fetched.response)); return
                        }
                        let responseURL = fetched.response.url ?? route.url
                        let body = route.kind == .playlist
                            ? try HLSPlaylist.rewrite(fetched.data, baseURL: responseURL) { try self.register($0, kind: $1) }
                            : fetched.data
                        let mime = HLSPlaylist.mimeType(data: body, upstreamType: fetched.response.mimeType, kind: route.kind, url: route.url)
                        self.respond(connection, id: id, status: fetched.response.statusCode, body: body, mime: mime,
                                     head: isHead, extra: route.kind == .playlist ? [:] : self.rangeHeaders(fetched.response))
                    } catch { self.respond(connection, id: id, status: 502) }
                }
            } catch {
                self?.queue.async { [weak self] in self?.respond(connection, id: id, status: 502) }
            }
        }
    }

    private func rangeHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var headers = ["Accept-Ranges": "bytes"]
        if let value = response.value(forHTTPHeaderField: "Content-Range"),
           value.range(of: #"^bytes (?:[0-9]+-[0-9]+|\*)/[0-9*]+$"#, options: .regularExpression) != nil {
            headers["Content-Range"] = value
        }
        return headers
    }

    private func respond(_ connection: NWConnection, id: UUID, status: Int, body: Data = Data(),
                         mime: String = "text/plain", head: Bool = false, extra: [String: String] = [:]) {
        guard connections[id] != nil else { return }
        let reason = [200: "OK", 206: "Partial Content", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 416: "Range Not Satisfiable", 431: "Request Header Fields Too Large", 502: "Bad Gateway"][status] ?? "Error"
        var header = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nContent-Type: \(mime)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for (key, value) in extra { header += "\(key): \(value)\r\n" }
        header += "\r\n"
        var response = Data(header.utf8)
        if !head { response.append(body) }
        connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in self?.finish(id) })
    }

    private func finish(_ id: UUID) {
        requests.removeValue(forKey: id)?.cancel()
        connections.removeValue(forKey: id)?.cancel()
    }

    fileprivate static func validateDestination(_ url: URL) async throws {
        guard HLSPlaylist.isPermitted(url), let host = url.host else { throw URLError(.unsupportedURL) }
        try await withCheckedThrowingContinuation { continuation in
            let pending = HLSDNSResult(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                pending.finish(publicDNS(host) ? .success(()) : .failure(URLError(.cannotFindHost)))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { pending.finish(.failure(URLError(.timedOut))) }
        }
    }

    private static func publicDNS(_ host: String) -> Bool {
        var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "443", &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }
        var pointer: UnsafeMutablePointer<addrinfo>? = first
        var found = false
        while let current = pointer {
            let entry = current.pointee
            guard let rawAddress = entry.ai_addr else { return false }
            if entry.ai_family == AF_INET {
                let address = UnsafeRawPointer(rawAddress).assumingMemoryBound(to: sockaddr_in.self).pointee
                let value = UInt32(bigEndian: address.sin_addr.s_addr)
                guard publicIPv4(value) else { return false }
                found = true
            } else if entry.ai_family == AF_INET6 {
                let address = UnsafeRawPointer(rawAddress).assumingMemoryBound(to: sockaddr_in6.self).pointee
                let bytes = withUnsafeBytes(of: address.sin6_addr) { Array($0) }
                guard bytes.count == 16 else { return false }
                // Support the well-known NAT64 prefix on IPv6-only cellular
                // networks, while checking its embedded IPv4 destination.
                if Array(bytes.prefix(12)) == [0, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0] {
                    let value = bytes.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    guard publicIPv4(value) else { return false }
                } else {
                    // Excludes loopback, link-local, unique-local and mapped IPs.
                    guard bytes[0] & 0xe0 == 0x20,
                          !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8) else { return false }
                }
                found = true
            }
            pointer = entry.ai_next
        }
        return found
    }

    private static func publicIPv4(_ value: UInt32) -> Bool {
        let a = value >> 24, b = (value >> 16) & 255
        return !(a == 0 || a == 10 || a == 127 || a >= 224 || (a == 100 && (64...127).contains(b)) ||
                 (a == 169 && b == 254) || (a == 172 && (16...31).contains(b)) ||
                 (a == 192 && (b == 168 || b == 0)) || (a == 198 && (b == 18 || b == 19)))
    }
}

private actor HLSFetchSlots {
    private var available = 4
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if available > 0 { available -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { available += 1 }
        else { waiters.removeFirst().resume() }
    }
}

private final class HLSDNSResult: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Void, Error>) {
        lock.lock(); let continuation = self.continuation; self.continuation = nil; lock.unlock()
        continuation?.resume(with: result)
    }
}

private final class HLSBoundedFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Value: @unchecked Sendable { let data: Data; let response: HTTPURLResponse }
    private let lock = NSLock()
    private let maximum = 32 * 1024 * 1024
    private var data = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<Value, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var redirects = 0

    func fetch(_ request: URLRequest) async throws -> Value {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
                configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 35
                let delegateQueue = OperationQueue(); delegateQueue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
                self.session = session
                let task = session.dataTask(with: request); self.task = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: { self.cancel() })
    }

    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 5, let url = request.url, HLSPlaylist.isPermitted(url) else { completionHandler(nil); return }
        Task {
            do {
                try await HLSLoopbackServer.validateDestination(url)
                var request = request
                request.setValue("https://cinejoy.pk/", forHTTPHeaderField: "Referer")
                request.setValue("https://cinejoy.pk", forHTTPHeaderField: "Origin")
                completionHandler(request)
            } catch { completionHandler(nil) }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse,
              response.expectedContentLength <= Int64(maximum) else { completionHandler(.cancel); return }
        self.response = response; completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count <= maximum - data.count else { dataTask.cancel(); return }
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let continuation = self.continuation; self.continuation = nil; self.task = nil; self.session = nil; lock.unlock()
        defer { session.finishTasksAndInvalidate() }
        if let error { continuation?.resume(throwing: error) }
        else if let response { continuation?.resume(returning: Value(data: data, response: response)) }
        else { continuation?.resume(throwing: URLError(.badServerResponse)) }
    }
}
