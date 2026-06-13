import Foundation
import CryptoKit

// Mints a short-lived ES256 JWT for the App Store Connect API.
// Reads credentials from environment (load your .env first):
//   ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH
// The .p8 private key itself is NEVER stored in the repo.

let env = ProcessInfo.processInfo.environment
guard let keyID = env["ASC_KEY_ID"], !keyID.isEmpty,
      let issuer = env["ASC_ISSUER_ID"], !issuer.isEmpty else {
    FileHandle.standardError.write(Data("Set ASC_KEY_ID and ASC_ISSUER_ID (source your .env)\n".utf8))
    exit(1)
}
let rawPath = env["ASC_PRIVATE_KEY_PATH"] ?? "~/.appstoreconnect/private_keys/AuthKey_\(keyID).p8"
let p8Path = NSString(string: rawPath).expandingTildeInPath

let pem = try String(contentsOfFile: p8Path, encoding: .utf8)
let key = try P256.Signing.PrivateKey(pemRepresentation: pem)

func b64(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
let header = #"{"alg":"ES256","kid":"\#(keyID)","typ":"JWT"}"#
let now = Int(Date().timeIntervalSince1970)
let payload = #"{"iss":"\#(issuer)","iat":\#(now),"exp":\#(now+1200),"aud":"appstoreconnect-v1"}"#
let signingInput = b64(Data(header.utf8)) + "." + b64(Data(payload.utf8))
let sig = try key.signature(for: Data(signingInput.utf8))
print(signingInput + "." + b64(sig.rawRepresentation))
