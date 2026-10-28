import Foundation
import Security

/// Who vouches for a program, from its code signature.
public enum CodeSigner: Sendable, Hashable {
    /// Signed by Apple: part of macOS or an Apple app.
    case apple
    case appStore(organization: String?)
    case developerID(organization: String?, teamID: String?, notarized: Bool)
    /// Signed with a certificate Apple didn't issue, as re-signed (cracked) copies of apps are.
    case untrustedCertificate(name: String?)
    /// Signed without an identity: common for things built locally and for Homebrew tools.
    case adHoc
    case unsigned
    /// A signature that no longer matches the program: it was changed after signing.
    case invalid
    /// macOS didn't let Dustpan look (e.g. the program file is unreadable).
    case unknown

    public var organization: String? {
        switch self {
        case .apple: "Apple"
        case .appStore(let organization), .developerID(let organization, _, _): organization
        case .untrustedCertificate(let name): name
        default: nil
        }
    }
}

public enum CodeTrust {
    private static func requirement(_ text: String) -> SecRequirement? {
        var requirement: SecRequirement?
        return SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess ? requirement : nil
    }

    private static let anchorApple = requirement("anchor apple")
    private static let appStore = requirement("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9]")
    private static let developerID = requirement("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]")
    private static let notarized = requirement("notarized")

    /// Checks a running process through the kernel's view of its code, falling back to the file on disk.
    public static func signer(pid: Int32, path: String?) -> CodeSigner {
        var code: SecCode?
        if SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess, let code {
            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .unknown }
            return classify(staticCode) { SecCodeCheckValidity(code, [], $0) }
        }
        guard let path else { return .unknown }
        return signer(path: path)
    }

    /// Checks a program file. Skips hashing bundle resources, which is slow and not needed to tell who signed it.
    public static func signer(path: String) -> CodeSigner {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return .unknown
        }
        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
        return classify(staticCode) { SecStaticCodeCheckValidity(staticCode, flags, $0) }
    }

    private static func classify(_ staticCode: SecStaticCode, check: (SecRequirement?) -> OSStatus) -> CodeSigner {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return .unknown }
        if info[kSecCodeInfoIdentifier as String] == nil { return .unsigned }

        switch check(nil) {
        case errSecSuccess: break
        case errSecCSUnsigned: return .unsigned
        default: return .invalid
        }
        let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        // kSecCodeSignatureAdhoc
        if flags & 0x0002 != 0 { return .adHoc }
        if check(anchorApple) == errSecSuccess { return .apple }

        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        let organization = (info[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first.flatMap(Self.organization)
        if check(appStore) == errSecSuccess { return .appStore(organization: organization) }
        if check(developerID) == errSecSuccess {
            return .developerID(organization: organization, teamID: teamID, notarized: check(notarized) == errSecSuccess)
        }
        // Apple-issued but not Developer ID (e.g. a development certificate) still has a team.
        if teamID != nil { return .developerID(organization: organization, teamID: teamID, notarized: false) }
        return .untrustedCertificate(name: organization)
    }

    /// "Developer ID Application: Slack Technologies, Inc. (BQR82RBBHL)" → "Slack Technologies, Inc."
    private static func organization(_ certificate: SecCertificate) -> String? {
        guard let summary = SecCertificateCopySubjectSummary(certificate) as String? else { return nil }
        var name = summary
        if let colon = name.firstIndex(of: ":") { name = String(name[name.index(after: colon)...]) }
        if let paren = name.lastIndex(of: "("), name.hasSuffix(")") { name = String(name[..<paren]) }
        return name.trimmingCharacters(in: .whitespaces)
    }
}
