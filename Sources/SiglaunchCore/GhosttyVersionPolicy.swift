enum GhosttyVersionPolicy {
  static let minimumVersion = "1.3.0"

  static func failure(for version: String?) -> PrimaryWorkflowFailure? {
    guard let version else { return .ghosttyVersionUnavailable }
    guard let semanticVersion = SemanticVersion(version) else {
      return .ghosttyVersionInvalid(version)
    }
    guard semanticVersion.isAtLeastStable(major: 1, minor: 3, patch: 0) else {
      return .ghosttyVersionUnsupported(
        found: version,
        minimum: minimumVersion
      )
    }
    return nil
  }

  private struct SemanticVersion {
    let major: Int
    let minor: Int
    let patch: Int
    let isPrerelease: Bool

    init?(_ value: String) {
      let buildParts = value.split(
        separator: "+",
        maxSplits: 1,
        omittingEmptySubsequences: false
      )
      guard buildParts.count <= 2 else { return nil }
      if buildParts.count == 2,
        !Self.validIdentifiers(
          buildParts[1],
          forbidLeadingZeroNumericIdentifiers: false
        )
      {
        return nil
      }

      let versionParts = buildParts[0].split(
        separator: "-",
        maxSplits: 1,
        omittingEmptySubsequences: false
      )
      let core = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
      guard
        core.count == 3,
        let major = Self.coreNumber(core[0]),
        let minor = Self.coreNumber(core[1]),
        let patch = Self.coreNumber(core[2])
      else {
        return nil
      }

      if versionParts.count == 2,
        !Self.validIdentifiers(
          versionParts[1],
          forbidLeadingZeroNumericIdentifiers: true
        )
      {
        return nil
      }

      self.major = major
      self.minor = minor
      self.patch = patch
      self.isPrerelease = versionParts.count == 2
    }

    func isAtLeastStable(major: Int, minor: Int, patch: Int) -> Bool {
      let versionCore = (self.major, self.minor, self.patch)
      let minimumCore = (major, minor, patch)
      if versionCore != minimumCore {
        return versionCore > minimumCore
      }
      return !isPrerelease
    }

    private static func coreNumber(_ value: Substring) -> Int? {
      guard
        isASCIIIdentifier(value, digitsOnly: true),
        value.count == 1 || value.first != "0"
      else {
        return nil
      }
      return Int(value)
    }

    private static func validIdentifiers(
      _ value: Substring,
      forbidLeadingZeroNumericIdentifiers: Bool
    ) -> Bool {
      let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
      guard !identifiers.isEmpty else { return false }

      return identifiers.allSatisfy { identifier in
        guard isASCIIIdentifier(identifier, digitsOnly: false) else { return false }
        guard
          forbidLeadingZeroNumericIdentifiers,
          isASCIIIdentifier(identifier, digitsOnly: true),
          identifier.count > 1
        else {
          return true
        }
        return identifier.first != "0"
      }
    }

    private static func isASCIIIdentifier(
      _ value: Substring,
      digitsOnly: Bool
    ) -> Bool {
      guard !value.isEmpty else { return false }
      return value.utf8.allSatisfy { byte in
        let isDigit = (48...57).contains(byte)
        if digitsOnly { return isDigit }
        return isDigit || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
      }
    }
  }
}
