import AppKit
import CryptoKit
import Darwin
import Foundation

/// The independent document engines bundled by the Mbs release.
///
/// These helpers are separate applications so they do not inherit the native
/// editor's account or feature-gate state.  The Mbs grant is still checked
/// before a helper is launched.
enum MbsIndependentEditorKind: String, CaseIterable {
    case word
    case sheet
    case slides
    case pdf

    var bundleName: String {
        switch self {
        case .word: return "MyAI Word.app"
        case .sheet: return "MyAI Excel.app"
        case .slides: return "MyAI Power Point.app"
        case .pdf: return "MyAI PDF.app"
        }
    }

    var displayName: String {
        switch self {
        case .word: return "文字编辑器"
        case .sheet: return "表格编辑器"
        case .slides: return "演示编辑器"
        case .pdf: return "PDF 工作台"
        }
    }
}

struct MbsIndependentLicenseStatus {
    let valid: Bool
    let reason: String
    let expiresAt: Date?
}

func MbsIndependentEditorAuthorizationStatus(now: Date = Date()) -> MbsIndependentLicenseStatus {
    MbsIndependentLicenseReader.current(now: now)
}

private enum MbsIndependentLicenseReader {
    private static let issuer = "https://ttys.ddxmu.com"
    private static let audience = "mbs.office.editor.custom"
    private static let authority = "mbs-custom"
    private static let maxGrantLifetime: TimeInterval = 30 * 24 * 60 * 60
    private static let publicKeyBase64 = "BGf8567bMEMYYRtG0JXCwBCFDyJ4ReEV05qY40deofCnpMhX0r5SRKe5Zs9suRBss73EXhtexOueXYeTMlUk0co="

    static func current(now: Date = Date()) -> MbsIndependentLicenseStatus {
        let account = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mbs Office/Account", isDirectory: true)
        guard let sessionData = ownerOnlyData(account.appendingPathComponent("session.json")),
              let grantData = ownerOnlyData(account.appendingPathComponent("editor-license.json")),
              let deviceData = ownerOnlyData(account.appendingPathComponent("device.id")),
              let session = jsonObject(sessionData),
              let envelope = jsonObject(grantData),
              let device = String(data: deviceData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let token = session["token"] as? String,
              let email = session["email"] as? String,
              let payloadText = envelope["payload"] as? String,
              let signatureText = envelope["signature"] as? String,
              let payload = Data(base64Encoded: payloadText),
              let signatureData = Data(base64Encoded: signatureText),
              let claims = jsonObject(payload) else {
            return MbsIndependentLicenseStatus(valid: false, reason: "缺少有效的 Mbs 在线授权", expiresAt: nil)
        }

        guard let publicData = Data(base64Encoded: publicKeyBase64),
              publicData.count == 65, publicData.first == 0x04,
              envelope["keyId"] as? String == "mbs-editor-p256-\(hex(SHA256.hash(data: publicData)).prefix(16))",
              let publicKey = try? P256.Signing.PublicKey(rawRepresentation: Data(publicData.dropFirst())),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
              publicKey.isValidSignature(signature, for: payload) else {
            return MbsIndependentLicenseStatus(valid: false, reason: "Mbs 授权签名无效", expiresAt: nil)
        }

        guard claims["version"] as? NSNumber == 1,
              claims["issuer"] as? String == issuer,
              claims["audience"] as? String == audience,
              claims["authority"] as? String == authority,
              claims["email"] as? String == email,
              claims["deviceId"] as? String == device,
              claims["sessionHash"] as? String == hex(SHA256.hash(data: Data(token.utf8))),
              let userID = claims["userId"] as? NSNumber, userID.int64Value > 0,
              let issuedAt = claims["issuedAt"] as? NSNumber,
              let expiresAt = claims["expiresAt"] as? NSNumber else {
            return MbsIndependentLicenseStatus(valid: false, reason: "Mbs 授权与当前账号或设备不匹配", expiresAt: nil)
        }

        let issued = issuedAt.doubleValue
        let expires = expiresAt.doubleValue
        let nowValue = now.timeIntervalSince1970
        guard issued <= nowValue + 300,
              expires > nowValue,
              expires > issued,
              expires - issued <= maxGrantLifetime else {
            return MbsIndependentLicenseStatus(valid: false, reason: "Mbs 授权已过期", expiresAt: Date(timeIntervalSince1970: expires))
        }

        if let activation = claims["activation"] as? [String: Any] {
            guard let plan = activation["plan"] as? String, plan == "standard" || plan == "vip",
                  activation["deviceId"] as? String == device,
                  let activationExpiry = activation["expiresAt"] as? NSNumber,
                  activationExpiry.doubleValue >= expires,
                  let maxDevices = activation["maxDevices"] as? NSNumber,
                  (1...10).contains(maxDevices.intValue) else {
                return MbsIndependentLicenseStatus(valid: false, reason: "Mbs 授权码绑定信息无效", expiresAt: nil)
            }
        }
        return MbsIndependentLicenseStatus(valid: true, reason: "Mbs 在线授权有效", expiresAt: Date(timeIntervalSince1970: expires))
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let object = value as? [String: Any] else { return nil }
        return object
    }

    private static func ownerOnlyData(_ url: URL) -> Data? {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == getuid(),
              (info.st_mode & 0o077) == 0,
              info.st_size > 0, info.st_size <= 16 * 1024,
              let data = try? Data(contentsOf: url), data.count <= 16 * 1024 else { return nil }
        return data
    }

    private static func hex<H: Sequence>(_ bytes: H) -> String where H.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

struct MbsIndependentEditorRouter {
    let bundleURL: URL

    init(bundleURL: URL = Bundle.main.bundleURL) {
        self.bundleURL = bundleURL
    }

    func kind(for url: URL) -> MbsIndependentEditorKind? {
        switch url.pathExtension.lowercased() {
        case "doc", "docx", "dot", "dotx", "dotm", "docm", "rtf": return .word
        case "xls", "xlsx", "xlsm", "xlt", "xltx", "xltm", "csv": return .sheet
        case "ppt", "pptx", "pptm", "pot", "potx", "potm": return .slides
        case "pdf": return .pdf
        default: return nil
        }
    }

    func helperURL(for kind: MbsIndependentEditorKind) -> URL {
        bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent(kind.bundleName, isDirectory: true)
    }

    /// Opens files handled by the independent suite and returns files that
    /// should continue through the legacy engine.  Unsupported formats do not
    /// get silently discarded.
    @discardableResult
    func open(_ urls: [URL], onActivationFailure: @escaping (String) -> Void) -> [URL] {
        let grouped = Dictionary(grouping: urls.compactMap { url -> (URL, MbsIndependentEditorKind)? in
            guard let kind = kind(for: url) else { return nil }
            return (url, kind)
        }, by: { $0.1 })
        let supported = grouped.values.flatMap { $0.map(\.0) }
        let fallback = urls.filter { kind(for: $0) == nil }
        guard !supported.isEmpty else { return fallback }

        let license = MbsIndependentLicenseReader.current()
        guard license.valid else {
            onActivationFailure(license.reason)
            return fallback
        }

        for (kind, entries) in grouped {
            let helper = helperURL(for: kind)
            guard FileManager.default.isExecutableFile(atPath: helper.appendingPathComponent("Contents/MacOS").path) else {
                onActivationFailure("找不到内置\(kind.displayName)，请重新安装完整 Mbs Office。")
                continue
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(entries.map(\.0), withApplicationAt: helper, configuration: configuration) { _, error in
                if let error {
                    onActivationFailure("\(kind.displayName)启动失败：\(error.localizedDescription)")
                }
            }
        }
        return fallback
    }

    func showActivationPrompt(reason: String) {
        let work = {
            let alert = NSAlert()
            alert.messageText = "需要 Mbs 在线授权"
            alert.informativeText = "\(reason)\n请登录 Mbs 账号并兑换授权码后重试。"
            alert.addButton(withTitle: "立即登录")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "https://ttys.ddxmu.com/mbs/login") {
                NSWorkspace.shared.open(url)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}
