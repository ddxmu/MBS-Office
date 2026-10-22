import Foundation

@main
struct IndependentEditorRouterTest {
    static func main() {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MBS_STAGE_APP"]!)
        let router = MbsIndependentEditorRouter(bundleURL: root)
        let cases: [(String, MbsIndependentEditorKind)] = [
            ("report.docx", .word), ("table.xlsx", .sheet),
            ("slides.pptx", .slides), ("manual.pdf", .pdf)
        ]
        for (name, expected) in cases {
            precondition(router.kind(for: URL(fileURLWithPath: "/tmp/\(name)")) == expected)
            precondition(FileManager.default.isExecutableFile(atPath: router.helperURL(for: expected)
                .appendingPathComponent("Contents/MacOS").path))
        }
        precondition(router.kind(for: URL(fileURLWithPath: "/tmp/archive.wps")) == nil)
        print("independent editor routes: ok")
    }
}
