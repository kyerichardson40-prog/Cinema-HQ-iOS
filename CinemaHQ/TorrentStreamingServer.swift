import Foundation
import Network

/// Serves only verified torrent bytes to AVPlayer, without exposing preallocated files.
final class TorrentStreamingServer: @unchecked Sendable {
    typealias Read = @Sendable (Range<Int64>) async throws -> Data

    private let fileLength: Int64
    private let contentType: String
    private let read: Read
    private let path = "/\(UUID().uuidString)/video.mp4"
    private let queue = DispatchQueue(label: "app.cinemahq.torrent-http")
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var clients: [UUID: Client] = [:]
    private var started = false
    private var stopped = false
    private static let chunkSize: Int64 = 65_536
    private static let maximumClients = 8

    init(fileLength: Int64, contentType: String = "video/mp4", read: @escaping Read) {
        self.fileLength = fileLength
        self.contentType = contentType
        self.read = read
    }

    func start() async throws -> URL {
        try Task.checkCancellation()
        let url: URL = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !self.started, !self.stopped else {
                        continuation.resume(throwing: ServerError.stopped)
                        return
                    }
                    self.started = true
                    guard self.fileLength > 0,
                          !self.contentType.contains("\r"), !self.contentType.contains("\n") else {
                        continuation.resume(throwing: ServerError.invalidFile)
                        return
                    }
                    do {
                        let parameters = NWParameters.tcp
                        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                        let listener = try NWListener(using: parameters)
                        self.listener = listener
                        self.startContinuation = continuation
                        listener.stateUpdateHandler = { [weak self] state in
                            guard let self else { return }
                            switch state {
                            case .ready:
                                guard let port = self.listener?.port,
                                      let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(self.path)") else {
                                    self.startContinuation?.resume(throwing: ServerError.invalidFile)
                                    self.startContinuation = nil
                                    self.listener?.cancel()
                                    return
                                }
                                self.startContinuation?.resume(returning: url)
                                self.startContinuation = nil
                            case .failed(let error):
                                self.startContinuation?.resume(throwing: error)
                                self.startContinuation = nil
                                self.stop()
                            case .cancelled:
                                self.startContinuation?.resume(throwing: ServerError.stopped)
                                self.startContinuation = nil
                            default: break
                            }
                        }
                        listener.newConnectionHandler = { [weak self] connection in
                            self?.accept(connection)
                        }
                        listener.start(queue: self.queue)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }, onCancel: { self.stop() })
        try Task.checkCancellation()
        return url
    }

    /// Cancels pending range reads as well as open sockets.
    func stop() {
        queue.async {
            guard !self.stopped else { return }
            self.stopped = true
            self.startContinuation?.resume(throwing: ServerError.stopped)
            self.startContinuation = nil
            self.listener?.cancel()
            self.listener?.stateUpdateHandler = nil
            self.listener?.newConnectionHandler = nil
            self.listener = nil
            let clients = Array(self.clients.values)
            self.clients.removeAll()
            for client in clients {
                client.task?.cancel()
                client.connection.cancel()
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped, clients.count < Self.maximumClients else {
            connection.cancel()
            return
        }
        let client = Client(connection: connection)
        clients[client.id] = client
        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .ready: self.receiveHeader(client)
            case .failed, .cancelled: self.finish(client)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak client] in
            guard let self, let client, !client.hasHeader else { return }
            self.finish(client)
        }
    }

    private func receiveHeader(_ client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) {
            [weak self, weak client] data, _, complete, error in
            guard let self, let client else { return }
            guard error == nil, !complete, let data, !data.isEmpty else {
                self.finish(client)
                return
            }
            client.header.append(data)
            guard client.header.count <= 16_384 else {
                self.respondError(client, status: 431, reason: "Request Header Fields Too Large")
                return
            }
            if let delimiter = client.header.range(of: Data([13, 10, 13, 10])) {
                client.hasHeader = true
                guard delimiter.upperBound == client.header.endIndex,
                      let text = String(data: client.header[..<delimiter.lowerBound], encoding: .utf8) else {
                    self.respondError(client, status: 400, reason: "Bad Request")
                    return
                }
                self.handle(text, client: client)
            } else {
                self.receiveHeader(client)
            }
        }
    }

    private func handle(_ header: String, client: Client) {
        let lines = header.components(separatedBy: "\r\n")
        let request = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, request[2] == "HTTP/1.1" || request[2] == "HTTP/1.0" else {
            respondError(client, status: 400, reason: "Bad Request")
            return
        }
        guard String(request[1]) == path else {
            respondError(client, status: 404, reason: "Not Found")
            return
        }
        let method = String(request[0])
        guard method == "GET" || method == "HEAD" else {
            respondError(client, status: 405, reason: "Method Not Allowed", extra: "Allow: GET, HEAD\r\n")
            return
        }
        var rangeHeader: String?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                respondError(client, status: 400, reason: "Bad Request")
                return
            }
            if line[..<colon].lowercased() == "range" {
                guard rangeHeader == nil else {
                    respondError(client, status: 400, reason: "Bad Request")
                    return
                }
                rangeHeader = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        let range: TorrentHTTPRange
        do {
            range = try TorrentHTTPRange(header: rangeHeader, fileLength: fileLength)
        } catch {
            respondError(client, status: 416, reason: "Range Not Satisfiable",
                         extra: "Content-Range: bytes */\(fileLength)\r\n")
            return
        }
        let status = range.partial ? "206 Partial Content" : "200 OK"
        var response = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nAccept-Ranges: bytes\r\nContent-Length: \(range.bytes.upperBound - range.bytes.lowerBound)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        if range.partial {
            response += "Content-Range: bytes \(range.bytes.lowerBound)-\(range.bytes.upperBound - 1)/\(fileLength)\r\n"
        }
        response += "\r\n"
        // A receive remains active while the read waits for peers. A closed player
        // connection then cancels the read and releases the engine's demand token.
        monitorDisconnect(client)
        client.task = Task { [weak self, weak client] in
            guard let self, let client else { return }
            do {
                try await Self.send(Data(response.utf8), to: client.connection, final: method == "HEAD")
                if method == "HEAD" {
                    self.closeAfterResponse(client)
                    return
                }
                var offset = range.bytes.lowerBound
                while offset < range.bytes.upperBound {
                    try Task.checkCancellation()
                    let end = offset + min(Self.chunkSize, range.bytes.upperBound - offset)
                    let bytes = try await self.read(offset..<end)
                    try Task.checkCancellation()
                    guard bytes.count == Int(end - offset) else { throw ServerError.invalidRead }
                    try await Self.send(bytes, to: client.connection, final: end == range.bytes.upperBound)
                    offset = end
                }
                self.closeAfterResponse(client)
            } catch {
                // Once headers have been sent, closing the socket reports an
                // incomplete range; no unverified or placeholder bytes are sent.
                self.queue.async { self.finish(client) }
            }
        }
    }

    private func monitorDisconnect(_ client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 1) {
            [weak self, weak client] data, _, complete, error in
            guard let self, let client else { return }
            if complete || error != nil || !(data?.isEmpty ?? true) {
                self.finish(client)
            } else {
                self.monitorDisconnect(client)
            }
        }
    }

    private func respondError(_ client: Client, status: Int, reason: String, extra: String = "") {
        client.hasHeader = true
        let response = "HTTP/1.1 \(status) \(reason)\r\n\(extra)Content-Length: 0\r\nConnection: close\r\n\r\n"
        client.task = Task { [weak self, weak client] in
            guard let self, let client else { return }
            do {
                try await Self.send(Data(response.utf8), to: client.connection, final: true)
                self.closeAfterResponse(client)
            } catch {
                self.queue.async { self.finish(client) }
            }
        }
    }

    private func closeAfterResponse(_ client: Client) {
        // finalMessage queues a TCP FIN after the response bytes. Allow the
        // reader to drain them before cancelling a socket it has not closed.
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak client] in
            guard let self, let client else { return }
            self.finish(client)
        }
    }

    private func finish(_ client: Client) {
        guard clients.removeValue(forKey: client.id) != nil else { return }
        client.task?.cancel()
        client.connection.stateUpdateHandler = nil
        client.connection.cancel()
    }

    private static func send(_ data: Data, to connection: NWConnection, final: Bool = false) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, contentContext: final ? .finalMessage : .defaultMessage,
                                isComplete: true, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
            try Task.checkCancellation()
        }, onCancel: { connection.cancel() })
    }

    private final class Client {
        let id = UUID()
        let connection: NWConnection
        var header = Data()
        var hasHeader = false
        var task: Task<Void, Never>?
        init(connection: NWConnection) { self.connection = connection }
    }

    enum ServerError: Error { case stopped, invalidFile, invalidRead }
}

struct TorrentHTTPRange {
    let bytes: Range<Int64>
    let partial: Bool

    init(header: String?, fileLength: Int64) throws {
        guard fileLength > 0 else { throw RangeError.unsatisfiable }
        guard let header else {
            bytes = 0..<fileLength
            partial = false
            return
        }
        guard header.hasPrefix("bytes="), !header.contains(",") else { throw RangeError.unsatisfiable }
        let bounds = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2 else { throw RangeError.unsatisfiable }
        func number(_ text: Substring) -> Int64? {
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int64(text)
        }
        if bounds[0].isEmpty {
            guard let suffix = number(bounds[1]), suffix > 0 else { throw RangeError.unsatisfiable }
            bytes = (fileLength - min(suffix, fileLength))..<fileLength
        } else {
            guard let start = number(bounds[0]), start < fileLength else { throw RangeError.unsatisfiable }
            if bounds[1].isEmpty {
                bytes = start..<fileLength
            } else {
                guard let end = number(bounds[1]), end >= start else { throw RangeError.unsatisfiable }
                // Clamp before incrementing, including Int64.max in a request.
                bytes = start..<(min(end, fileLength - 1) + 1)
            }
        }
        partial = true
    }

    enum RangeError: Error { case unsatisfiable }
}
