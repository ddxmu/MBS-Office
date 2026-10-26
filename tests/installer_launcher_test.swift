import Foundation

@main
enum InstallerLauncherTest {
    static func main() {
        let app = URL(fileURLWithPath:"/Applications/Mbs Office.app")
        precondition(mbsShouldCloseLauncher(app,app:app))
        precondition(!mbsShouldCloseLauncher(nil,app:app))
        precondition(!mbsShouldCloseLauncher(app.appendingPathComponent("Contents/Resources/MbsEngine.app"),app:app))
        precondition(!mbsShouldCloseLauncher(URL(fileURLWithPath:"/Applications/Mbs Office copy.app"),app:app))
        precondition(!mbsShouldCloseLauncher(URL(fileURLWithPath:"/Applications/Other.app"),app:app))
        print("PASS: only the exact outer launcher is eligible for a normal quit; editor and other copies excluded")
    }
}
