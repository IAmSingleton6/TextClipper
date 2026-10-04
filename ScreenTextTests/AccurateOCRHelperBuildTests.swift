import Foundation
@testable import ScreenText
import Security
import Testing

@Suite(.timeLimit(.minutes(1)))
struct AccurateOCRHelperBuildTests {
    @Test func `embedded helper preserves exactly the sandbox inheritance entitlements`() throws {
        let executable = try #require(Bundle.main.executableURL)
        let helper = executable.deletingLastPathComponent().appendingPathComponent("AccurateOCRHelper")
        var code: SecStaticCode?
        #expect(SecStaticCodeCreateWithPath(helper as CFURL, [], &code) == errSecSuccess)
        let signedCode = try #require(code)
        var information: CFDictionary?
        #expect(SecCodeCopySigningInformation(
            signedCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information,
        ) == errSecSuccess)
        let details = try #require(information as? [String: Any])
        let entitlements = try #require(details[kSecCodeInfoEntitlementsDict as String] as? [String: Bool])
        #expect(entitlements == [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.inherit": true,
        ])
    }
}
