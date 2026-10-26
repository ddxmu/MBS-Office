import Foundation
import AppKit
import CryptoKit
import Darwin

// Public verification key only. The signing private key is never part of this target.
let MBS_UPDATE_PUBLIC_KEY_BASE64 = "zqO3kFJM+TcQKbDXS/RQEpW8aKRVrdZ8bTmVQjnX4kA="
let mbsModuleLimit = 100 * 1024 * 1024
let mbsEnginePrefix = "Contents/Resources/MbsEngine.app/"
let mbsModulePaths: Set<String> = Set([
    "Contents/MacOS/MbsLauncher",
    mbsEnginePrefix + "Contents/MacOS/MbsOfflineFlags.dylib",
    "Contents/Resources/MbsModuleInstaller",
    "Contents/Resources/MbsUpdatePublicKey.bin",
]).union(["wps", "et", "wpp", "pdf"].map {
    mbsEnginePrefix + "Contents/Resources/office6/res/commands/\($0)/ongmani/CT_MbsAI.kuip"
})

struct MbsInstallerError: Error, CustomStringConvertible {
    let code: String
    let description: String
    init(_ code: String, _ message: String) { self.code = code; description = message }
}

struct MbsModuleFile: Codable {
    let path: String
    let sha256: String
}
struct MbsModuleManifest: Codable {
    let format: String
    let fromVersion: String
    let toVersion: String
    let files: [MbsModuleFile]
}
struct MbsZipEntry {
    let name: String
    let isDirectory: Bool
    let size: Int
}
struct MbsVerifiedPackage {
    let manifest: MbsModuleManifest
    let contents: [String: Data]
}

func mbsVersion(_ value: String) -> [Int]? {
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count == 3 else { return nil }
    var numbers: [Int] = []
    for part in components {
        guard !part.isEmpty, part.count <= 9,
              part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              part.count == 1 || part.first != "0", let number = Int(part) else { return nil }
        numbers.append(number)
    }
    return numbers
}
func mbsVersionIsNewer(_ next: String, than current: String) -> Bool {
    guard let a = mbsVersion(next), let b = mbsVersion(current) else { return false }
    for i in 0..<3 { if a[i] != b[i] { return a[i] > b[i] } }
    return false
}
func mbsHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
func mbsSafeRelativeName(_ name: String) -> Bool {
    guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"),
          name.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return false }
    let path = name.hasSuffix("/") ? String(name.dropLast()) : name
    return !path.split(separator: "/", omittingEmptySubsequences: false)
        .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
}
func mbsParentNames(_ files: Set<String>) -> Set<String> {
    var result: Set<String> = []
    for file in files {
        var parts = file.split(separator: "/").map(String.init)
        while parts.count > 1 {
            parts.removeLast()
            result.insert(parts.joined(separator: "/") + "/")
        }
    }
    return result
}

func mbsNoSymlinks(_ url: URL) throws {
    var current = URL(fileURLWithPath: "/", isDirectory: true)
    for component in url.standardizedFileURL.pathComponents.dropFirst() {
        current.appendPathComponent(component)
        var info = stat()
        if lstat(current.path, &info) == 0 {
            if info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) {
                throw MbsInstallerError("symlink", "更新路径包含符号链接，已停止安装。")
            }
        } else if errno != ENOENT {
            throw MbsInstallerError("path_unreadable", "无法检查更新路径。")
        }
    }
}
func mbsRegularData(_ url: URL, limit: Int) throws -> Data {
    try mbsNoSymlinks(url)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
          let bytes = attributes[.size] as? NSNumber, bytes.int64Value > 0,
          bytes.int64Value <= Int64(limit) else {
        throw MbsInstallerError("input_size", "更新文件类型或大小不符合要求。")
    }
    let data = try Data(contentsOf: url)
    guard data.count > 0, data.count <= limit else {
        throw MbsInstallerError("input_changed", "更新文件在读取时发生变化。")
    }
    return data
}

// No shell is used. A closed output pipe bounds malformed archive expansion;
// no signals are sent to an editor or other application process.
@discardableResult
func mbsTool(_ executable: String, _ arguments: [String], outputLimit: Int = 64 * 1024) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    var output = Data()
    var oversized = false
    do {
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
            if chunk.count > outputLimit - output.count { oversized = true; break }
            output.append(chunk)
        }
    } catch {
        try? pipe.fileHandleForReading.close()
        process.waitUntilExit()
        throw MbsInstallerError("tool_output", "无法读取更新工具的结果。")
    }
    try? pipe.fileHandleForReading.close()
    process.waitUntilExit()
    guard !oversized, process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw MbsInstallerError("tool_failed", "更新文件或系统工具未通过检查。")
    }
    return output
}

func mbsU16(_ bytes: Data, _ offset: Int) throws -> Int {
    guard offset >= 0, offset + 2 <= bytes.count else {
        throw MbsInstallerError("zip_bounds", "更新压缩包结构不完整。")
    }
    return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
}
func mbsU32(_ bytes: Data, _ offset: Int) throws -> Int {
    let low = try mbsU16(bytes, offset)
    return low | (try mbsU16(bytes, offset + 2)) << 16
}

// Inspect central AND local headers before asking unzip to read any entry.
// ZIP64, encryption, special files, duplicate names and zip bombs are unnecessary
// for these eight small self-developed files and are rejected.
func mbsZipInventory(_ bytes: Data) throws -> [MbsZipEntry] {
    guard bytes.count >= 22, bytes.count <= mbsModuleLimit else {
        throw MbsInstallerError("zip_size", "更新压缩包大小不符合要求。")
    }
    var endRecord: Int?
    for offset in stride(from: bytes.count - 22, through: max(0,bytes.count - 65557), by: -1) {
        if try mbsU32(bytes,offset) == 0x06054b50,
           offset + 22 + (try mbsU16(bytes,offset + 20)) == bytes.count {
            endRecord = offset; break
        }
    }
    guard let end = endRecord else { throw MbsInstallerError("zip_end", "无法识别更新压缩包。") }
    let count = try mbsU16(bytes,end + 10)
    let centralSize = try mbsU32(bytes,end + 12)
    let centralStart = try mbsU32(bytes,end + 16)
    guard try mbsU16(bytes,end + 4) == 0, try mbsU16(bytes,end + 6) == 0,
          try mbsU16(bytes,end + 8) == count, count > 0, count <= 64,
          centralStart + centralSize == end else {
        throw MbsInstallerError("zip_format", "更新压缩包格式不受支持。")
    }
    var cursor = centralStart
    var names: Set<String> = []
    var entries: [MbsZipEntry] = []
    var expanded = 0
    let permittedDirectories = mbsParentNames(mbsModulePaths)
    for _ in 0..<count {
        guard try mbsU32(bytes,cursor) == 0x02014b50 else {
            throw MbsInstallerError("zip_directory", "更新压缩包索引无效。")
        }
        let flags = try mbsU16(bytes,cursor + 8)
        let method = try mbsU16(bytes,cursor + 10)
        let compressed = try mbsU32(bytes,cursor + 20)
        let size = try mbsU32(bytes,cursor + 24)
        let nameSize = try mbsU16(bytes,cursor + 28)
        let extraSize = try mbsU16(bytes,cursor + 30)
        let commentSize = try mbsU16(bytes,cursor + 32)
        let external = try mbsU32(bytes,cursor + 38)
        let local = try mbsU32(bytes,cursor + 42)
        let next = cursor + 46 + nameSize + extraSize + commentSize
        guard next <= end, nameSize > 0, try mbsU16(bytes,cursor + 34) == 0,
              flags & 0x2041 == 0, method == 0 || method == 8 else {
            throw MbsInstallerError("zip_entry", "更新压缩包包含不支持的条目。")
        }
        let nameData = bytes.subdata(in: cursor + 46..<cursor + 46 + nameSize)
        guard let name = String(data: nameData,encoding: .ascii), mbsSafeRelativeName(name),
              names.insert(name).inserted else {
            throw MbsInstallerError("zip_path", "更新压缩包包含重复或非法路径。")
        }
        let directory = name.hasSuffix("/")
        let mode = (external >> 16) & 0xf000
        guard mode == 0 || mode == (directory ? 0x4000 : 0x8000),
              directory ? permittedDirectories.contains(name) : (name == "manifest.json" || mbsModulePaths.contains(name)),
              size <= mbsModuleLimit, !directory || size == 0 else {
            throw MbsInstallerError("zip_not_module", "更新包包含非自研模块、链接或特殊文件。")
        }
        guard try mbsU32(bytes,local) == 0x04034b50,
              try mbsU16(bytes,local + 6) == flags, try mbsU16(bytes,local + 8) == method else {
            throw MbsInstallerError("zip_local", "更新压缩包的文件头不一致。")
        }
        let localNameSize = try mbsU16(bytes,local + 26)
        let localExtraSize = try mbsU16(bytes,local + 28)
        let body = local + 30 + localNameSize + localExtraSize
        guard localNameSize == nameSize, body + compressed <= centralStart,
              local + 30 + localNameSize <= bytes.count,
              bytes.subdata(in: local + 30..<local + 30 + localNameSize) == nameData else {
            throw MbsInstallerError("zip_local_path", "更新压缩包的文件路径不一致。")
        }
        expanded += size
        guard expanded <= mbsModuleLimit, name != "manifest.json" || size <= 65536 else {
            throw MbsInstallerError("zip_expansion", "更新压缩包解压后超出模块大小限制。")
        }
        entries.append(MbsZipEntry(name:name,isDirectory:directory,size:size))
        cursor = next
    }
    guard cursor == end, names.contains("manifest.json") else {
        throw MbsInstallerError("zip_manifest", "更新包缺少有效清单。")
    }
    return entries
}

func mbsValidateManifest(_ manifest: MbsModuleManifest, entries: [MbsZipEntry], current: String) throws {
    guard manifest.format == "mbs-modules-v1", manifest.fromVersion == current,
          mbsVersion(current) != nil, mbsVersionIsNewer(manifest.toVersion,than:current),
          !manifest.files.isEmpty, manifest.files.count <= mbsModulePaths.count else {
        throw MbsInstallerError("manifest_version", "更新清单不适配当前 Mbs Office 版本。")
    }
    var files: Set<String> = []
    for file in manifest.files {
        guard mbsModulePaths.contains(file.path), files.insert(file.path).inserted,
              file.sha256.utf8.count == 64,
              file.sha256.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw MbsInstallerError("manifest_files", "更新清单包含非法模块或校验值。")
        }
    }
    let listed = Set(entries.filter { !$0.isDirectory }.map(\.name))
    guard listed == files.union(["manifest.json"]),
          Set(entries.filter(\.isDirectory).map(\.name)).isSubset(of: mbsParentNames(files)) else {
        throw MbsInstallerError("manifest_extra", "更新包中的文件与清单不一致。")
    }
}

func mbsVerifySignature(package: Data, signature: Data, key: Data) throws {
    guard package.count > 0, package.count <= mbsModuleLimit, signature.count == 64, key.count == 32,
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation:key),
          publicKey.isValidSignature(signature,for:package) else {
        throw MbsInstallerError("signature", "更新包签名无效，未进行安装。")
    }
}

func mbsVerifyPackage(zip: URL, signatureFile: URL, current: String) throws -> MbsVerifiedPackage {
    let bytes = try mbsRegularData(zip,limit:mbsModuleLimit)
    let signatureText = try mbsRegularData(signatureFile,limit:4096)
    guard let encoded = String(data:signatureText,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines),
          let signature = Data(base64Encoded:encoded), let key = Data(base64Encoded:MBS_UPDATE_PUBLIC_KEY_BASE64) else {
        throw MbsInstallerError("signature_encoding", "更新包签名格式无效。")
    }
    try mbsVerifySignature(package:bytes,signature:signature,key:key)
    let entries = try mbsZipInventory(bytes)
    let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("MbsModules-\(UUID().uuidString)",isDirectory:true)
    try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:false,
                                            attributes:[.posixPermissions:0o700])
    defer { try? FileManager.default.removeItem(at:temporary) }
    let snapshot = temporary.appendingPathComponent("signed.zip")
    try bytes.write(to:snapshot,options:.atomic)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:snapshot.path)
    let listing = try mbsTool("/usr/bin/unzip",["-Z1",snapshot.path])
    guard let inventoryText = String(data:listing,encoding:.utf8) else {
        throw MbsInstallerError("zip_inventory", "无法读取更新包文件列表。")
    }
    var inventory = inventoryText.components(separatedBy:"\n")
    if inventory.last == "" { inventory.removeLast() }
    guard inventory.count == entries.count, Set(inventory).count == entries.count,
          Set(inventory) == Set(entries.map(\.name)) else {
        throw MbsInstallerError("zip_inventory", "系统工具识别的更新包路径不一致。")
    }
    guard let manifestEntry = entries.first(where: { $0.name == "manifest.json" }) else {
        throw MbsInstallerError("manifest_missing", "更新清单不存在。")
    }
    let manifestData = try mbsTool("/usr/bin/unzip",["-p",snapshot.path,"manifest.json"],outputLimit:manifestEntry.size)
    let manifest: MbsModuleManifest
    do { manifest = try JSONDecoder().decode(MbsModuleManifest.self,from:manifestData) }
    catch { throw MbsInstallerError("manifest_json", "更新清单格式无效。") }
    try mbsValidateManifest(manifest,entries:entries,current:current)
    var contents: [String:Data] = [:]
    for file in manifest.files {
        let entry = entries.first { $0.name == file.path }!
        let data = try mbsTool("/usr/bin/unzip",["-p",snapshot.path,file.path],outputLimit:entry.size)
        guard data.count == entry.size, mbsHash(data) == file.sha256.lowercased() else {
            throw MbsInstallerError("file_sha256", "更新模块未通过 SHA-256 校验。")
        }
        contents[file.path] = data
    }
    return MbsVerifiedPackage(manifest:manifest,contents:contents)
}

func mbsInfo(_ app: URL) throws -> [String:Any] {
    let plist = app.appendingPathComponent("Contents/Info.plist")
    try mbsNoSymlinks(plist)
    guard let dictionary = try PropertyListSerialization.propertyList(from:Data(contentsOf:plist),options:[],format:nil) as? [String:Any] else {
        throw MbsInstallerError("app_info", "无法读取目标应用信息。")
    }
    return dictionary
}
func mbsTarget(_ rawPath: String) throws -> (URL,String) {
    guard rawPath.hasPrefix("/"), !rawPath.split(separator:"/").contains(where: { $0 == "." || $0 == ".." }) else {
        throw MbsInstallerError("app_path", "请指定外层 Mbs Office 应用的绝对路径。")
    }
    let app = URL(fileURLWithPath:rawPath).standardizedFileURL
    guard app.path != "/", app.pathExtension == "app", !app.path.contains("/Contents/Resources/") else {
        throw MbsInstallerError("app_target", "目标必须是外层 Mbs Office 应用。")
    }
    try mbsNoSymlinks(app)
    let attributes = try FileManager.default.attributesOfItem(atPath:app.path)
    let information = try mbsInfo(app)
    guard attributes[.type] as? FileAttributeType == .typeDirectory,
          information["CFBundleIdentifier"] as? String == "com.mbs.office.launcher",
          let version = information["CFBundleShortVersionString"] as? String, mbsVersion(version) != nil else {
        throw MbsInstallerError("app_identity", "目标不是可更新的 Mbs Office 应用。")
    }
    let values = try app.resourceValues(forKeys:[.volumeIsReadOnlyKey])
    guard values.volumeIsReadOnly == false,
          FileManager.default.isWritableFile(atPath:app.deletingLastPathComponent().path) else {
        throw MbsInstallerError("app_readonly", "应用所在位置不可写，请先将 Mbs Office 移到可写位置。")
    }
    return (app,version)
}

func mbsProcessPath(_ pid: Int32) throws -> String? {
    var buffer = [CChar](repeating:0,count:4096)
    let length = proc_pidpath(pid,&buffer,UInt32(buffer.count))
    if length > 0 { return String(cString:buffer) }
    if errno == ESRCH || errno == ENOENT { return nil }
    throw MbsInstallerError("process_identity", "无法确认编辑器进程状态，已停止安装。")
}
func mbsApplicationProcesses(_ app: URL) -> [NSRunningApplication] {
    ["com.mbs.office.wps","com.mbs.office.launcher"].flatMap {
        NSRunningApplication.runningApplications(withBundleIdentifier:$0)
    }.filter {
        $0.processIdentifier != getpid() && !$0.isTerminated &&
        ($0.bundleURL?.standardizedFileURL == app ||
         $0.bundleURL?.standardizedFileURL == app.appendingPathComponent("Contents/Resources/MbsEngine.app"))
    }
}
func mbsWaitForExit(_ pid: Int32, app: URL, timeout: TimeInterval = 180) throws {
    let expected = app.appendingPathComponent("Contents/Resources/MbsEngine.app/Contents/MacOS/wpsoffice").path
    if let path = try mbsProcessPath(pid), path != expected {
        throw MbsInstallerError("pid_mismatch", "等待的进程不属于此 Mbs Office 应用。")
    }
    let deadline = Date().addingTimeInterval(timeout)
    var notifiedLaunchers = Set<Int32>()
    while Date() < deadline {
        let path = try mbsProcessPath(pid)
        if path == nil || path != expected {
            let running = mbsApplicationProcesses(app)
            if running.isEmpty { return }
            // The outer launcher owns no documents. Once the editor has exited,
            // ask a leftover launcher to quit normally before replacing its app.
            // Never terminate an editor or a different installed copy here.
            for process in running where mbsShouldCloseLauncher(process.bundleURL, app:app) {
                if notifiedLaunchers.insert(process.processIdentifier).inserted { process.terminate() }
            }
        }
        Thread.sleep(forTimeInterval:0.25)
    }
    throw MbsInstallerError("editor_still_open", "编辑器仍在运行。请完成保存并正常退出后重新升级；未强制关闭任何进程。")
}
func mbsShouldCloseLauncher(_ bundle: URL?, app: URL) -> Bool {
    bundle?.standardizedFileURL == app.standardizedFileURL
}
func mbsLaunch(_ app: URL) throws {
    try mbsTool("/usr/bin/open",["-n",app.path])
}
func mbsConfirmLaunch(_ app: URL, timeout: TimeInterval = 30) -> Bool {
    let engine = app.appendingPathComponent("Contents/Resources/MbsEngine.app").standardizedFileURL
    let deadline = Date().addingTimeInterval(timeout)
    var firstSeen: Date?
    while Date() < deadline {
        if mbsApplicationProcesses(app).contains(where: {
            $0.bundleURL?.standardizedFileURL == engine && $0.isFinishedLaunching && !$0.isTerminated
        }) {
            if let first = firstSeen, Date().timeIntervalSince(first) >= 2 { return true }
            if firstSeen == nil { firstSeen = Date() }
        } else { firstSeen = nil }
        Thread.sleep(forTimeInterval:0.25)
    }
    return false
}

func mbsWritePlist(_ dictionary: [String:Any], app: URL) throws {
    let url = app.appendingPathComponent("Contents/Info.plist")
    try mbsNoSymlinks(url)
    try PropertyListSerialization.data(fromPropertyList:dictionary,format:.xml,options:0).write(to:url,options:.atomic)
}
func mbsSetEditorDisplayName(_ engine: URL) throws {
    let resources = engine.appendingPathComponent("Contents/Resources")
    let names = ["InfoPlist.strings", "zh-Hans.lproj/InfoPlist.strings",
                 "zh-Hant.lproj/InfoPlist.strings", "office6/zh-Hans.lproj/InfoPlist.strings",
                 "office6/zh-Hant.lproj/InfoPlist.strings"]
    let pattern = try NSRegularExpression(pattern:#"("CFBundle(?:DisplayName|Name)"\s*=\s*)"[^"]*""#)
    for name in names {
        let file = resources.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath:file.path) else { continue }
        try mbsNoSymlinks(file)
        let text = try String(contentsOf:file,encoding:.utf8)
        let updated = pattern.stringByReplacingMatches(in:text,range:NSRange(text.startIndex...,in:text),
                                                       withTemplate:"$1\"Mbs Office\"")
        if updated != text { try updated.write(to:file,atomically:true,encoding:.utf8) }
    }
}
func mbsPrepareStage(_ app: URL, package: MbsVerifiedPackage, stage: URL) throws {
    try mbsTool("/usr/bin/ditto",[app.path,stage.path])
    for (path,data) in package.contents {
        let destination = stage.appendingPathComponent(path)
        try mbsNoSymlinks(destination)
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:destination,options:.atomic)
        let executable = path == "Contents/MacOS/MbsLauncher" || path == "Contents/Resources/MbsModuleInstaller"
        try FileManager.default.setAttributes([.posixPermissions:executable ? 0o755 : 0o644],ofItemAtPath:destination.path)
        let values = try destination.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink == false,
              mbsHash(try Data(contentsOf:destination)) == mbsHash(data) else {
            throw MbsInstallerError("stage_module", "暂存模块未通过检查。")
        }
    }
    var outer = try mbsInfo(stage)
    outer["CFBundleShortVersionString"] = package.manifest.toVersion
    if let build = outer["CFBundleVersion"] as? String, let number = Int(build), number < Int.max {
        outer["CFBundleVersion"] = String(number + 1)
    }
    try mbsWritePlist(outer,app:stage)
    let engine = stage.appendingPathComponent("Contents/Resources/MbsEngine.app")
    var inner = try mbsInfo(engine)
    guard inner["CFBundleIdentifier"] as? String == "com.mbs.office.wps" else {
        throw MbsInstallerError("engine_identity", "暂存应用的编辑组件身份不匹配。")
    }
    inner["MbsModuleVersion"] = package.manifest.toVersion
    try mbsWritePlist(inner,app:engine)
    try mbsSetEditorDisplayName(engine)
    let library = engine.appendingPathComponent("Contents/MacOS/MbsOfflineFlags.dylib")
    for target in [library,stage.appendingPathComponent("Contents/Resources/MbsModuleInstaller"),engine,stage] {
        try mbsNoSymlinks(target)
        try mbsTool("/usr/bin/codesign",["--force","--sign","-",target.path])
    }
    try mbsTool("/usr/bin/codesign",["--verify","--deep","--strict",stage.path])
}

func mbsSupport() throws -> URL {
    let base = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
    let support = base.appendingPathComponent("Mbs Office",isDirectory:true)
    try mbsNoSymlinks(support)
    try FileManager.default.createDirectory(at:support,withIntermediateDirectories:true)
    return support
}
func mbsJSON(_ value: [String:Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
}
var mbsInstallerResultDetails: [String:Any] = [:]
func mbsResult(_ state: String, _ message: String, extra: [String:Any] = [:], persist: Bool = true) {
    if persist { mbsInstallerResultDetails = extra }
    var value = extra
    value["format"] = "mbs-update-result-v1"
    value["state"] = state
    value["message"] = message
    value["timestamp"] = ISO8601DateFormatter().string(from:Date())
    do {
        let data = try mbsJSON(value)
        if persist {
            let directory = try mbsSupport().appendingPathComponent("Updates",isDirectory:true)
            try mbsNoSymlinks(directory)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let file = directory.appendingPathComponent("status.json")
            try mbsNoSymlinks(file)
            try data.write(to:file,options:.atomic)
        }
        // Older app versions launch us with pipes that close when they quit.
        // The persisted receipt remains authoritative if a reader disappears.
        try? FileHandle.standardOutput.write(contentsOf:data + Data([10]))
    } catch {
        // Never print package contents, signatures, keys, or subprocess output.
        try? FileHandle.standardError.write(contentsOf:Data("无法保存更新状态。\n".utf8))
    }
}

// Only an entry identified by our prior receipt is eligible for pruning.
// Unrecognized files and apps in the rollback directory are never removed.
func mbsStoreRollback(_ previous: URL, app: URL, version: String) throws -> URL {
    let root = try mbsSupport().appendingPathComponent("Rollback",isDirectory:true)
    try mbsNoSymlinks(root)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let receipt = root.appendingPathComponent("receipt.json")
    try mbsNoSymlinks(receipt)
    var older: URL?
    if FileManager.default.fileExists(atPath:receipt.path) {
        guard let record = try JSONSerialization.jsonObject(with:Data(contentsOf:receipt)) as? [String:String],
              record["format"] == "mbs-rollback-v1", let name = record["name"],
              name.hasPrefix("previous-"), name.hasSuffix(".app"),
              UUID(uuidString:String(name.dropFirst(9).dropLast(4))) != nil else {
            throw MbsInstallerError("rollback_receipt", "回滚目录已有无法识别的记录，旧版备份仍保留在应用原目录。")
        }
        let candidate = root.appendingPathComponent(name)
        try mbsNoSymlinks(candidate)
        if FileManager.default.fileExists(atPath:candidate.path) {
            let information = try mbsInfo(candidate)
            guard information["CFBundleIdentifier"] as? String == "com.mbs.office.launcher",
                  information["CFBundleShortVersionString"] as? String == record["version"] else {
                throw MbsInstallerError("rollback_identity", "上次回滚备份身份不匹配，未删除任何现有备份。")
            }
            older = candidate
        }
    }
    let destination = root.appendingPathComponent("previous-\(UUID().uuidString).app",isDirectory:true)
    // Copy first, preserving the adjacent backup until the receipt is durable.
    try mbsTool("/usr/bin/ditto",[previous.path,destination.path])
    let record = ["format":"mbs-rollback-v1","name":destination.lastPathComponent,
                  "version":version,"sourceApp":app.path]
    do { try mbsJSON(record).write(to:receipt,options:.atomic) }
    catch { try? FileManager.default.removeItem(at:destination); throw error }
    try FileManager.default.removeItem(at:previous)
    if let older { try FileManager.default.removeItem(at:older) }
    return destination
}

struct MbsInstallerArguments {
    let package: URL
    let signature: URL
    let appPath: String
    let waitPID: Int32?
    let verifyOnly: Bool
    init(_ arguments: [String]) throws {
        var values: [String:String] = [:]
        var verify = false
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            if key == "--verify-only" {
                guard !verify else { throw MbsInstallerError("arguments", "重复的安装参数。") }
                verify = true; index += 1; continue
            }
            guard ["--package","--signature","--app","--wait-pid"].contains(key),
                  values[key] == nil, index + 1 < arguments.count else {
                throw MbsInstallerError("arguments", "安装参数不完整或无效。")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        guard let packagePath = values["--package"], packagePath.hasPrefix("/"),
              let signaturePath = values["--signature"], signaturePath.hasPrefix("/"),
              let app = values["--app"], app.hasPrefix("/") else {
            throw MbsInstallerError("arguments", "请提供更新包、签名和外层应用的绝对路径。")
        }
        let pid = values["--wait-pid"].flatMap(Int32.init)
        guard verify || (pid != nil && pid! > 0 && pid! != getpid()) else {
            throw MbsInstallerError("arguments", "请提供要等待正常退出的编辑器进程。")
        }
        if values["--wait-pid"] != nil && (pid == nil || pid! <= 0 || pid! == getpid()) {
            throw MbsInstallerError("arguments", "编辑器进程参数无效。")
        }
        package = URL(fileURLWithPath:packagePath)
        signature = URL(fileURLWithPath:signaturePath)
        appPath = app
        waitPID = pid
        verifyOnly = verify
    }
}

func mbsInstall(_ arguments: MbsInstallerArguments) throws {
    let (app,current) = try mbsTarget(arguments.appPath)
    let package = try mbsVerifyPackage(zip:arguments.package,signatureFile:arguments.signature,current:current)
    var details: [String:Any] = ["fromVersion":current,"toVersion":package.manifest.toVersion,
                               "installed":false,"restarted":false,"rolledBack":false]
    if arguments.verifyOnly {
        mbsResult("verified","更新包签名、模块清单和文件校验通过，尚未修改应用。",extra:details,persist:false)
        return
    }
    let pid = arguments.waitPID!
    let expected = app.appendingPathComponent("Contents/Resources/MbsEngine.app/Contents/MacOS/wpsoffice").path
    if let path = try mbsProcessPath(pid), path != expected {
        throw MbsInstallerError("pid_mismatch", "等待的进程不属于此 Mbs Office 应用。")
    }
    let parent = app.deletingLastPathComponent()
    let transaction = UUID().uuidString
    let stage = parent.appendingPathComponent(".MbsOffice-stage-\(transaction).app",isDirectory:true)
    let previous = parent.appendingPathComponent(".MbsOffice-previous-\(transaction).app",isDirectory:true)
    defer { if FileManager.default.fileExists(atPath:stage.path) { try? FileManager.default.removeItem(at:stage) } }
    mbsResult("preparing","正在准备自研模块更新，原应用尚未替换。",extra:details)
    try mbsPrepareStage(app,package:package,stage:stage)
    mbsResult("waiting","请保存文档并正常退出 Mbs Office，安装器正在等待。",extra:details)
    try mbsWaitForExit(pid,app:app)
    guard try mbsInfo(app)["CFBundleShortVersionString"] as? String == current else {
        throw MbsInstallerError("app_changed", "目标应用版本已改变，请重新检查更新。")
    }
    mbsResult("installing","正在替换已验证的 Mbs 自研模块。",extra:details)
    try FileManager.default.moveItem(at:app,to:previous)
    do { try FileManager.default.moveItem(at:stage,to:app) }
    catch {
        do { try FileManager.default.moveItem(at:previous,to:app) }
        catch { throw MbsInstallerError("rollback_failed", "应用替换失败，旧版仍保留在相邻备份目录，需手动恢复。") }
        throw MbsInstallerError("swap_failed", "应用替换失败，已恢复旧版。")
    }
    details["installed"] = true
    mbsResult("restarting","自研模块已替换，正在确认新版本启动。",extra:details)
    var confirmed = false
    do { try mbsLaunch(app); confirmed = mbsConfirmLaunch(app) } catch { confirmed = false }
    if !confirmed && mbsApplicationProcesses(app).isEmpty {
        do {
            try FileManager.default.moveItem(at:app,to:stage)
            try FileManager.default.moveItem(at:previous,to:app)
            details["installed"] = false
            details["rolledBack"] = true
            try? mbsLaunch(app)
            mbsResult("failed","新版本未能启动，已恢复旧版并请求重新打开。",extra:details)
            throw MbsInstallerError("restart_rolled_back", "新版本未能启动，已恢复旧版。")
        } catch let error as MbsInstallerError { throw error }
        catch { throw MbsInstallerError("rollback_failed", "重启失败且无法自动恢复，旧版备份仍予以保留。") }
    }
    var backup = previous
    var backupWarning = false
    do { backup = try mbsStoreRollback(previous,app:app,version:current) }
    catch { backupWarning = true }
    details["backupPath"] = backup.path
    details["restarted"] = confirmed
    if !confirmed {
        mbsResult("restart_unconfirmed","新版本已写入但启动尚未确认；未强制关闭任何进程，旧版备份已保留。",extra:details)
        return
    }
    mbsResult("completed",backupWarning ?
        "更新已安装并确认启动；回滚备份保留在应用原目录，请检查回滚目录状态。" :
        "Mbs 自研模块已更新并重新启动，已保留上一版本用于回滚。",extra:details)
}

#if !MBS_INSTALLER_TESTS
@main
enum MbsModuleInstallerMain {
    static func main() {
        signal(SIGPIPE,SIG_IGN)
        let verify = CommandLine.arguments.contains("--verify-only")
        do {
            let arguments = try MbsInstallerArguments(Array(CommandLine.arguments.dropFirst()))
            try mbsInstall(arguments)
        } catch let error as MbsInstallerError {
            var details = mbsInstallerResultDetails
            details["errorCode"] = error.code
            mbsResult("failed",error.description,extra:details,persist:!verify)
            exit(1)
        } catch {
            var details = mbsInstallerResultDetails
            details["errorCode"] = "system_error"
            mbsResult("failed","更新未完成，原有备份不会被自动删除。",extra:details,persist:!verify)
            exit(1)
        }
    }
}
#endif
