import Foundation

@main
enum BundleDisplayNameTest {
    static func main() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/MbsDisplayNameTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let resources = root.appendingPathComponent("Contents/Resources")
        let names = ["InfoPlist.strings", "zh-Hans.lproj/InfoPlist.strings",
                     "office6/zh-Hant.lproj/InfoPlist.strings"]
        let original = "// Copyright WPS Office\n\"CFBundleName\" = \"WPS Office\";\n\"CFBundleDisplayName\" = \"WPS Office\";\n\"OtherKey\" = \"WPS Office\";\n"
        let expected = original.replacingOccurrences(of:"= \"WPS Office\";",with:"= \"Mbs Office\";")
            .replacingOccurrences(of:"\"OtherKey\" = \"Mbs Office\";",with:"\"OtherKey\" = \"WPS Office\";")
        for name in names {
            let file = resources.appendingPathComponent(name)
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try original.write(to:file,atomically:true,encoding:.utf8)
        }
        try mbsSetEditorDisplayName(root)
        try mbsSetEditorDisplayName(root)
        for name in names {
            let actual = try String(contentsOf:resources.appendingPathComponent(name),encoding:.utf8)
            precondition(actual == expected)
        }
        let linked = resources.appendingPathComponent("zh-Hans.lproj/InfoPlist.strings")
        let outside = root.appendingPathComponent("outside.strings")
        try original.write(to:outside,atomically:true,encoding:.utf8)
        try FileManager.default.removeItem(at:linked)
        try FileManager.default.createSymbolicLink(at:linked,withDestinationURL:outside)
        do {
            try mbsSetEditorDisplayName(root)
            fatalError("A linked resource must not be rewritten")
        } catch is MbsInstallerError { }
        let unchanged = try String(contentsOf:outside,encoding:.utf8)
        precondition(unchanged == original)
        print("Default and localized display names, preservation, idempotency and symlink checks passed.")
    }
}
