public enum AppVersion {
    /// Single source of truth for the app/CLI version. Bump on release.
    /// The `v<this>` git tag must match it (the release workflow checks), and
    /// scripts/package.sh reads it for the bundle's Info.plist.
    public static let string = "0.1.0"
}
