import Foundation

/// Pure parsing shared by the loopback proxy and its command-line regression check.
enum HLSPlaylist {
    enum ResourceKind: String, Sendable { case playlist, media, key, metadata }

    static func isPermitted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(), !host.hasSuffix(".") else { return false }
        return host == "lightspeed.st" || host.hasSuffix(".lightspeed.st")
    }

    static func rewrite(_ data: Data, baseURL: URL,
                        localURL: (URL, ResourceKind) throws -> URL) throws -> Data {
        guard let text = String(data: data, encoding: .utf8),
              text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else {
            throw URLError(.cannotDecodeContentData)
        }
        let attribute = try NSRegularExpression(pattern: #"(?<=[,:])([A-Z0-9-]*URI)="([^"]*)""#)
        var nextIsPlaylist = false
        let rewritten = try text.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return line }
            if !trimmed.hasPrefix("#") {
                let kind: ResourceKind = nextIsPlaylist || trimmed.lowercased().contains(".m3u8") ? .playlist : .media
                nextIsPlaylist = false
                guard let upstream = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
                      isPermitted(upstream) else { throw URLError(.unsupportedURL) }
                return try localURL(upstream, kind).absoluteString
            }
            if trimmed.hasPrefix("#EXT-X-STREAM-INF:") { nextIsPlaylist = true }
            var result = line
            for match in attribute.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let range = Range(match.range(at: 2), in: result) else { continue }
                let value = String(result[range])
                guard let upstream = URL(string: value, relativeTo: baseURL)?.absoluteURL,
                      isPermitted(upstream) else { throw URLError(.unsupportedURL) }
                let kind: ResourceKind
                if trimmed.hasPrefix("#EXT-X-KEY:") || trimmed.hasPrefix("#EXT-X-SESSION-KEY:") { kind = .key }
                else if trimmed.hasPrefix("#EXT-X-SESSION-DATA:") || trimmed.hasPrefix("#EXT-X-CONTENT-STEERING:") { kind = .metadata }
                else if upstream.path.lowercased().hasSuffix(".m3u8") || trimmed.hasPrefix("#EXT-X-RENDITION-REPORT:") { kind = .playlist }
                else { kind = .media }
                result.replaceSubrange(range, with: try localURL(upstream, kind).absoluteString)
            }
            return result
        }.joined(separator: "\n")
        return Data(rewritten.utf8)
    }

    static func mimeType(data: Data, upstreamType: String?, kind: ResourceKind, url: URL) -> String {
        if kind == .playlist { return "application/vnd.apple.mpegurl" }
        if kind == .key { return "application/octet-stream" }
        let bytes = [UInt8](data.prefix(16))
        if bytes.count >= 8, let box = String(bytes: bytes[4..<8], encoding: .ascii),
           ["ftyp", "styp", "moof", "moov"].contains(box) { return "video/mp4" }
        if bytes.starts(with: [87, 69, 66, 86, 84, 84]) || url.path.lowercased().hasSuffix(".vtt") { return "text/vtt" }
        if bytes.first == 0x47 || url.path.lowercased().hasSuffix(".ts") { return "video/mp2t" }
        if bytes.count > 1, bytes[0] == 0xff, bytes[1] & 0xf6 == 0xf0 { return "audio/aac" }
        if let type = upstreamType?.components(separatedBy: ";").first?.lowercased(),
           type.hasPrefix("video/") || type.hasPrefix("audio/") || type == "application/json" { return type }
        // Ranged fMP4 responses need not contain their initial box. The observed
        // provider calls these .png/image/png, so media routes retain an MP4 MIME.
        return kind == .media ? "video/mp4" : "application/octet-stream"
    }

    static func validRange(_ value: String) -> Bool {
        value.range(of: #"^bytes=(?:[0-9]{1,18}-[0-9]{0,18}|-[0-9]{1,18})$"#, options: .regularExpression) != nil
    }
}
