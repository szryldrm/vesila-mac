import Foundation
import CryptoKit

// Independent verification against the public key embedded in the archived app.
do {
    guard CommandLine.arguments.count == 4,
          let key = Data(base64Encoded: CommandLine.arguments[2]), key.count == 32,
          let signature = Data(base64Encoded: CommandLine.arguments[3]), signature.count == 64 else {
        throw NSError(domain: "VesilaUpdate", code: 1)
    }
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    guard publicKey.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "VesilaUpdate", code: 2)
    }
} catch {
    FileHandle.standardError.write(Data("Archive signature does not match the bundled public key (or input is invalid).\n".utf8))
    exit(1)
}
