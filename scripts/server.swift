// Voice server for Claude Code (macOS).
// Native languages → proxy to Anthropic's server.
// Unsupported languages (Hebrew, etc.) → Apple SFSpeechRecognizer on-device.

import Foundation
import Network
import Speech
import AppKit

let PORT: UInt16 = 19876
let ANTHROPIC_WS = "wss://api.anthropic.com/api/ws/speech_to_text/voice_stream"
let NATIVE_LANGS: Set<String> = ["en","es","fr","ja","de","pt","it","ko","hi","id","ru","pl","tr","nl","uk","el","cs","da","sv","no"]

// MARK: - Language

let localeMap: [String: String] = [
    "he": "he-IL", "hebrew": "he-IL", "עברית": "he-IL",
    "en": "en-US", "english": "en-US",
    "es": "es-ES", "spanish": "es-ES", "español": "es-ES",
    "fr": "fr-FR", "french": "fr-FR", "français": "fr-FR",
    "de": "de-DE", "german": "de-DE", "deutsch": "de-DE",
    "ja": "ja-JP", "japanese": "ja-JP", "日本語": "ja-JP",
    "ko": "ko-KR", "korean": "ko-KR", "한국어": "ko-KR",
    "pt": "pt-BR", "portuguese": "pt-BR", "português": "pt-BR",
    "it": "it-IT", "italian": "it-IT", "italiano": "it-IT",
    "ru": "ru-RU", "russian": "ru-RU", "русский": "ru-RU",
    "zh": "zh-CN", "chinese": "zh-CN",
    "yue": "zh-HK", "cantonese": "zh-HK", "廣東話": "zh-HK", "广东话": "zh-HK", "粵語": "zh-HK",
    "zh-hk": "zh-HK",
    "ar": "ar-SA", "arabic": "ar-SA",
    "hi": "hi-IN", "hindi": "hi-IN",
    "id": "id-ID", "indonesian": "id-ID",
    "tr": "tr-TR", "turkish": "tr-TR",
    "nl": "nl-NL", "dutch": "nl-NL",
    "pl": "pl-PL", "polish": "pl-PL",
    "uk": "uk-UA", "ukrainian": "uk-UA",
    "el": "el-GR", "greek": "el-GR",
    "cs": "cs-CZ", "czech": "cs-CZ",
    "da": "da-DK", "danish": "da-DK",
    "sv": "sv-SE", "swedish": "sv-SE",
    "no": "nb-NO", "norwegian": "nb-NO",
]

func readLanguage() -> String {
    let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    guard let data = try? Data(contentsOf: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let lang = json["language"] as? String else { return "en" }
    return lang.lowercased().trimmingCharacters(in: .whitespaces)
}

func langCode(_ raw: String) -> String {
    if NATIVE_LANGS.contains(raw) { return raw }
    if let mapped = localeMap[raw] { return String(mapped.prefix(2)) }
    return raw
}

func appleLocale(_ raw: String) -> String {
    return localeMap[raw] ?? localeMap[langCode(raw)] ?? "en-US"
}

func isNativeLanguage(_ raw: String) -> Bool {
    return NATIVE_LANGS.contains(langCode(raw))
}

// MARK: - OAuth token

func readOAuthToken() -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    proc.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let json = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String else { return nil }
    return token
}

// MARK: - WAV + Apple STT

func createWav(_ pcm: Data) -> Data {
    var w = Data(count: 44)
    func u32(_ o: Int, _ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { w.replaceSubrange(o..<o+4, with: $0) } }
    func u16(_ o: Int, _ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { w.replaceSubrange(o..<o+2, with: $0) } }
    w.replaceSubrange(0..<4, with: "RIFF".data(using: .ascii)!)
    u32(4, UInt32(36 + pcm.count))
    w.replaceSubrange(8..<12, with: "WAVE".data(using: .ascii)!)
    w.replaceSubrange(12..<16, with: "fmt ".data(using: .ascii)!)
    u32(16, 16); u16(20, 1); u16(22, 1)
    u32(24, 16000); u32(28, 32000); u16(32, 2); u16(34, 16)
    w.replaceSubrange(36..<40, with: "data".data(using: .ascii)!)
    u32(40, UInt32(pcm.count))
    w.append(pcm)
    return w
}

func transcribeApple(_ pcm: Data, locale: String, completion: @escaping (String) -> Void) {
    guard !pcm.isEmpty else { return completion("") }
    let dur = String(format: "%.1f", Double(pcm.count) / 32000.0)
    print("[voice] \(dur)s → Apple STT (\(locale))")

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("hv-\(ProcessInfo.processInfo.globallyUniqueString).wav")
    try? createWav(pcm).write(to: tmp)

    guard let rec = SFSpeechRecognizer(locale: Locale(identifier: locale)), rec.isAvailable else {
        try? FileManager.default.removeItem(at: tmp)
        return completion("")
    }
    let req = SFSpeechURLRecognitionRequest(url: tmp)
    req.shouldReportPartialResults = false
    if rec.supportsOnDeviceRecognition {
        req.requiresOnDeviceRecognition = true
        print("[voice] On-device")
    }
    rec.recognitionTask(with: req) { result, _ in
        try? FileManager.default.removeItem(at: tmp)
        let text = result?.isFinal == true ? result!.bestTranscription.formattedString : ""
        if !text.isEmpty { print("[voice] \"\(text)\"") }
        completion(text)
    }
}

// MARK: - WebSocket helpers

func sendJSON(_ conn: NWConnection, _ dict: [String: String]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
    let meta = NWProtocolWebSocket.Metadata(opcode: .text)
    let ctx = NWConnection.ContentContext(identifier: "ws", metadata: [meta])
    conn.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
}

// MARK: - Proxy session (native languages → Anthropic)

class ProxySession {
    let conn: NWConnection
    var upstream: URLSessionWebSocketTask?

    init(_ conn: NWConnection, lang: String, token: String) {
        self.conn = conn
        let params = "encoding=linear16&sample_rate=16000&channels=1&endpointing_ms=300&utterance_end_ms=1000&language=\(lang)"
        let url = URL(string: "\(ANTHROPIC_WS)?\(params)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("cli", forHTTPHeaderField: "x-app")
        upstream = URLSession.shared.webSocketTask(with: request)
        upstream?.resume()
        receiveFromUpstream()
        receiveFromClient()
        print("[voice] Proxying to Anthropic (\(lang))")
    }

    // Client → Anthropic
    func receiveFromClient() {
        conn.receiveMessage { [weak self] data, ctx, _, error in
            guard let self = self, let data = data, error == nil else { return }
            let meta = ctx?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            switch meta?.opcode {
            case .text:
                self.upstream?.send(.string(String(data: data, encoding: .utf8) ?? "")) { _ in }
            case .binary:
                self.upstream?.send(.data(data)) { _ in }
            default: break
            }
            self.receiveFromClient()
        }
    }

    // Anthropic → Client
    func receiveFromUpstream() {
        upstream?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let text):
                    let meta = NWProtocolWebSocket.Metadata(opcode: .text)
                    let ctx = NWConnection.ContentContext(identifier: "ws", metadata: [meta])
                    self.conn.send(content: text.data(using: .utf8), contentContext: ctx, isComplete: true, completion: .idempotent)
                case .data(let data):
                    let meta = NWProtocolWebSocket.Metadata(opcode: .binary)
                    let ctx = NWConnection.ContentContext(identifier: "ws", metadata: [meta])
                    self.conn.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
                @unknown default: break
                }
                self.receiveFromUpstream()
            case .failure:
                break
            }
        }
    }
}

// MARK: - Local session (unsupported languages → Apple STT)

class LocalSession {
    var chunks: [Data] = []
    var closed = false
    let locale: String

    init(locale: String) { self.locale = locale }

    func receive(_ conn: NWConnection) {
        conn.receiveMessage { [self] data, ctx, _, error in
            guard let data = data, error == nil else { return }
            let meta = ctx?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            switch meta?.opcode {
            case .binary: if !closed { chunks.append(data) }
            case .text: handleText(conn, data)
            default: break
            }
            receive(conn)
        }
    }

    func handleText(_ conn: NWConnection, _ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        if type == "KeepAlive" { return }
        if type == "CloseStream" && !closed {
            closed = true
            sendJSON(conn, ["type": "TranscriptText", "data": ""])
            let pcm = chunks.reduce(Data()) { $0 + $1 }
            chunks = []
            transcribeApple(pcm, locale: locale) { text in
                if !text.isEmpty { sendJSON(conn, ["type": "TranscriptText", "data": text]) }
                sendJSON(conn, ["type": "TranscriptEndpoint"])
            }
        }
    }
}

// MARK: - Server

var activeSessions: [ObjectIdentifier: AnyObject] = [:]

func startServer() {
    let params = NWParameters.tcp
    let ws = NWProtocolWebSocket.Options()
    params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)

    guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: PORT)!) else {
        print("[voice] Failed to start on port \(PORT)")
        return
    }
    listener.newConnectionHandler = { conn in
        conn.start(queue: .main)
        let raw = readLanguage()
        let code = langCode(raw)

        if isNativeLanguage(raw), let token = readOAuthToken() {
            print("[voice] Connected (\(code) → Anthropic)")
            let session = ProxySession(conn, lang: code, token: token)
            activeSessions[ObjectIdentifier(session)] = session
        } else {
            let locale = appleLocale(raw)
            print("[voice] Connected (\(locale) → Apple STT)")
            let session = LocalSession(locale: locale)
            activeSessions[ObjectIdentifier(session)] = session
            session.receive(conn)
        }

        conn.stateUpdateHandler = { state in
            if case .cancelled = state { activeSessions.removeAll() }
            if case .failed = state { activeSessions.removeAll() }
        }
    }
    listener.start(queue: .main)
    print("[voice] Voice server on ws://127.0.0.1:\(PORT)")
    print("[voice] Native languages → Anthropic | Others → Apple STT")
}

// MARK: - App entry

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            startServer()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    if status == .authorized { startServer() }
                    else {
                        print("[voice] Speech Recognition denied. Grant in System Settings > Privacy > Speech Recognition.")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
