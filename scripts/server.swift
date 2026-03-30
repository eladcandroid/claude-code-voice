// Voice server for Claude Code (macOS).
// WebSocket server + Apple SFSpeechRecognizer in a single binary.
// Reads language from ~/.claude/settings.json — switch via /config.

import Foundation
import Network
import Speech
import AppKit

let PORT: UInt16 = 19876

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

func currentLocale() -> String {
    let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    guard let data = try? Data(contentsOf: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let lang = json["language"] as? String else { return "en-US" }
    let key = lang.lowercased().trimmingCharacters(in: .whitespaces)
    return localeMap[key] ?? (key.contains("-") ? key : "en-US")
}

// MARK: - WAV

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

// MARK: - Speech recognition

func transcribe(_ pcm: Data, completion: @escaping (String) -> Void) {
    guard !pcm.isEmpty else { return completion("") }

    let locale = currentLocale()
    let dur = String(format: "%.1f", Double(pcm.count) / 32000.0)
    print("[voice] \(dur)s → \(locale)")

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("hv-\(ProcessInfo.processInfo.globallyUniqueString).wav")
    try? createWav(pcm).write(to: tmp)

    guard let rec = SFSpeechRecognizer(locale: Locale(identifier: locale)), rec.isAvailable else {
        print("[voice] Recognizer unavailable for \(locale), falling back to en-US")
        if let fallback = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), fallback.isAvailable {
            recognize(fallback, tmp, completion)
        } else {
            try? FileManager.default.removeItem(at: tmp)
            completion("")
        }
        return
    }
    recognize(rec, tmp, completion)
}

func recognize(_ rec: SFSpeechRecognizer, _ url: URL, _ completion: @escaping (String) -> Void) {
    let req = SFSpeechURLRecognitionRequest(url: url)
    req.shouldReportPartialResults = false
    if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }

    rec.recognitionTask(with: req) { result, _ in
        try? FileManager.default.removeItem(at: url)
        let text = result?.isFinal == true ? result!.bestTranscription.formattedString : ""
        if !text.isEmpty { print("[voice] \"\(text)\"") }
        completion(text)
    }
}

// MARK: - WebSocket server

func sendJSON(_ conn: NWConnection, _ dict: [String: String]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
    let meta = NWProtocolWebSocket.Metadata(opcode: .text)
    let ctx = NWConnection.ContentContext(identifier: "ws", metadata: [meta])
    conn.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
}

class Session {
    var chunks: [Data] = []
    var closed = false

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
            transcribe(pcm) { text in
                if !text.isEmpty { sendJSON(conn, ["type": "TranscriptText", "data": text]) }
                sendJSON(conn, ["type": "TranscriptEndpoint"])
            }
        }
    }
}

func startServer() {
    let params = NWParameters.tcp
    let ws = NWProtocolWebSocket.Options()
    params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)

    guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: PORT)!) else {
        print("[voice] Failed to start on port \(PORT)")
        return
    }
    listener.newConnectionHandler = { conn in
        print("[voice] Connected (\(currentLocale()))")
        let session = Session()
        conn.start(queue: .main)
        session.receive(conn)
    }
    listener.start(queue: .main)
    print("[voice] Voice server on ws://127.0.0.1:\(PORT) (Apple STT)")
}

// MARK: - App entry (needed for macOS TCC permission)

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
