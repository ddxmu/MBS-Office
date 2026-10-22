import Foundation

@main
struct IndependentEditorLicenseTest {
    static func main() {
        let status = MbsIndependentEditorAuthorizationStatus()
        guard status.valid else {
            fputs("invalid: \(status.reason)\n", stderr)
            exit(1)
        }
        print("valid")
        if let expiresAt = status.expiresAt {
            print("expires=\(Int(expiresAt.timeIntervalSince1970))")
        }
    }
}
