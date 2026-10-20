import Foundation
import CryptoKit

let directory = URL(fileURLWithPath:CommandLine.arguments[1])
let key = try Curve25519.Signing.PrivateKey(rawRepresentation:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
guard key.publicKey.rawRepresentation.base64EncodedString() == "zqO3kFJM+TcQKbDXS/RQEpW8aKRVrdZ8bTmVQjnX4kA=" else {
    fatalError("Update signing identity mismatch")
}
let packages = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
    .filter { $0.pathExtension == "zip" }
for package in packages {
    let data = try Data(contentsOf:package)
    let signature = try key.signature(for:data)
    guard key.publicKey.isValidSignature(signature,for:data) else { fatalError("Signature verification failed") }
    try (signature.base64EncodedString()+"\n").write(to:URL(fileURLWithPath:package.path+".sig"),atomically:true,encoding:.utf8)
}
let assets = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
    .filter { $0.lastPathComponent != "checksums.sha256" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
let checksums = try assets.map { file in
    SHA256.hash(data:try Data(contentsOf:file)).map { String(format:"%02x",$0) }.joined()+"  "+file.lastPathComponent
}.joined(separator:"\n")+"\n"
try checksums.write(to:directory.appendingPathComponent("checksums.sha256"),atomically:true,encoding:.utf8)
print("Signed and verified \(packages.count) module package(s)")
