// Release.swift

/// The FOSUtilities release this scaffolder ships with.
///
/// Generated projects pin FOSUtilities `from:` this version, and the CLI reports
/// it as its own version — the scaffolder and the framework release together.
///
/// RELEASE RITUAL: the CHANGELOG stamp commit updates this constant. The
/// release-stamp test in FOSMVVMBootstrapTests compares it against the topmost
/// stamped CHANGELOG release and fails CI when they disagree.
public enum Release {
    public static let version = "0.13.3"
}
