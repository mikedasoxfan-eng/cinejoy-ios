import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let base = URL(string: "https://lightspeed.st/hls/example/master.m3u8?opaque=private")!
var mapped: [(URL, HLSPlaylist.ResourceKind)] = []
let original = """
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="en",URI="audio/index.m3u8?token=a,b"
#EXT-X-STREAM-INF:BANDWIDTH=400000,CODECS="avc1.4D401E,mp4a.40.2"
../video/360.m3u8?token=x
#EXT-X-MAP:URI="/hls/init.png?token=map",BYTERANGE="200@0"
#EXT-X-KEY:METHOD=AES-128,URI="https://cdn.lightspeed.st/hls/key.bin"
#EXTINF:4.0,
segment.png?token=seg
#EXT-X-RENDITION-REPORT:URI="live.m3u8",LAST-MSN=4
#EXT-X-CONTENT-STEERING:SERVER-URI="steering.json"
#EXT-X-ENDLIST
"""
let rewritten = try HLSPlaylist.rewrite(Data(original.utf8), baseURL: base) { url, kind in
    mapped.append((url, kind))
    return URL(string: "http://127.0.0.1:1234/token/\(mapped.count).bin")!
}
let output = String(decoding: rewritten, as: UTF8.self)
check(mapped.count == 7, "Every playlist, segment, map, key, report and steering URI is rewritten")
check(mapped[0].0.absoluteString == "https://lightspeed.st/hls/example/audio/index.m3u8?token=a,b", "Quoted commas remain part of the source URL")
check(mapped[1].0.path == "/hls/video/360.m3u8" && mapped[1].1 == .playlist, "Variants resolve relative paths")
check(mapped[2].0.path == "/hls/init.png" && mapped[2].1 == .media, "Root map URI keeps media role")
check(mapped[3].1 == .key && mapped[4].1 == .media, "Key and segment resource roles differ")
check(mapped[5].1 == .playlist && mapped[6].1 == .metadata, "Rendition and steering resource roles differ")
check(!output.contains("opaque=private") && !output.contains("token=seg") && !output.contains("lightspeed.st"), "Local playlists contain no upstream signed URLs")
check(output.contains(#"BYTERANGE="200@0""#) && output.contains(#"CODECS="avc1.4D401E,mp4a.40.2""#), "Non-URI tags and quoted commas remain unchanged")

for invalid in ["http://lightspeed.st/a.m3u8", "https://lightspeed.st.evil.test/a", "https://127.0.0.1/a", "https://lightspeed.st:444/a", "https://user:password@lightspeed.st/a"] {
    check(!HLSPlaylist.isPermitted(URL(string: invalid)!), "Reject unapproved origin \(invalid)")
}
do {
    _ = try HLSPlaylist.rewrite(Data("#EXTM3U\nhttp://127.0.0.1/media.m3u8".utf8), baseURL: base) { _, _ in base }
    preconditionFailure("Unsafe playlist destinations must be rejected")
} catch {}

let ftyp = Data([0, 0, 0, 24] + Array("ftypisom".utf8))
check(HLSPlaylist.mimeType(data: ftyp, upstreamType: "image/png", kind: .media, url: base) == "video/mp4", "MP4 magic overrides the provider's PNG MIME")
check(HLSPlaylist.mimeType(data: Data([1, 2, 3]), upstreamType: "image/png", kind: .media, url: base) == "video/mp4", "Ranged media keeps MP4 MIME without an initial box")
check(HLSPlaylist.mimeType(data: Data("WEBVTT\n".utf8), upstreamType: "image/png", kind: .media, url: base) == "text/vtt", "WebVTT keeps text MIME")
check(HLSPlaylist.validRange("bytes=0-1") && HLSPlaylist.validRange("bytes=1024-") && HLSPlaylist.validRange("bytes=-1024"), "Support single byte-range forms")
check(!HLSPlaylist.validRange("bytes=0-1,5-6") && !HLSPlaylist.validRange("bytes=0-1\r\nInjected: yes"), "Reject multiple or injected ranges")
print("HLS rewrite, origin, MIME and range checks passed")
