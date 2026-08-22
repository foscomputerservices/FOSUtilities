// HandoffChecklist.swift

/// Human finishing steps the tooling structurally cannot do.
public enum HandoffChecklist {
    /// The finishing steps to print after a project is scaffolded, keyed to
    /// its shape — e.g.
    /// `print(HandoffChecklist.text(for: config.shape, projectName: config.projectName))`.
    /// For `.sharedLibrary` this lists the git-init, doctrine-read, and
    /// first-ViewModel steps the scaffolder cannot perform for the user;
    /// for `.localOnly` it also names the Xcode-only finishing moves (signing, ⌘U)
    /// around the generated `<projectName>.xcodeproj` (whose source folders are
    /// already Xcode 16 synchronized folders — no manual conversion).
    public static func text(for shape: ProjectShape, projectName: String) -> String {
        switch shape {
        case .sharedLibrary:
            """

            Next steps:
            1. git init && git add -A && git commit  (the tool does not create the repo)
            2. Read CLAUDE.md and memory/ — settled doctrine ships with the project.
            3. Add ViewModels via the fosmvvm-viewmodel-generator skill.
            """
        case .localOnly:
            """

            Next steps (things tooling structurally cannot do):
            1. git init && git add -A && git commit
            2. Open \(projectName).xcodeproj in Xcode:
               a. The source folders are Xcode 16 synchronized folders — files
                  add/remove automatically, and the pbxproj does not churn in SCC.
                  project.yml stays the source of truth; regenerate any time with
                  `xcodegen generate`.
               b. Confirm signing: your real DEVELOPMENT_TEAM on every target.
               c. Run the test suite (⌘U). Note: `xcodebuild build-for-testing`
                  on macOS fails at Ld for this layout — a known Xcode
                  limitation (memory/macos-build-for-testing-faq.md). Tests run
                  fine from Xcode and on the iOS Simulator.
               d. Add iOS/iPadOS destinations if wanted.
            3. Read CLAUDE.md and memory/ — settled doctrine ships with the project.
            4. Add screens via the fosmvvm-viewmodel-generator +
               fosmvvm-swiftui-view-generator skills.
            """
        case .clientServer:
            """

            Next steps (things tooling structurally cannot do):
            1. git init && git add -A && git commit
            2. Server:
               a. swift run \(projectName)Server   (boots on http://localhost:8080)
               b. It seeds a demo Board+Card into a SQLite file. Set real
                  production / staging deployment URLs in \(projectName)App.swift.
            3. App — open \(projectName).xcodeproj in Xcode:
               a. The source folders are Xcode 16 synchronized folders — files
                  add/remove automatically, and the shared "\(projectName)ViewModels"
                  folder is compiled INTO the app on purpose (the SPM lib compiles
                  it too, for the server). project.yml stays the source of truth;
                  regenerate any time with `xcodegen generate` — no per-file churn.
               b. Attach \(projectName).xctestplan to the scheme's Test action
                  (Product → Scheme → Edit → Test → + the plan). XcodeGen can't
                  wire it with stable UUIDs; the scheme already lists the three
                  test targets, so ⌘U works either way.
               c. Confirm signing: your real DEVELOPMENT_TEAM.
               d. Run the app (Board tab fetches the live board; add a card and it
                  refreshes). Add iOS/iPadOS destinations if wanted.
            4. Read CLAUDE.md and memory/ — settled doctrine ships with the project.
            5. Add screens via the fosmvvm-viewmodel-generator +
               fosmvvm-serverrequest-generator + fosmvvm-fluent-datamodel-generator
               + fosmvvm-swiftui-view-generator skills. Replace the grant-all
               SkeletonAuthProvider with a credential-scoped provider.
            """
        case .hybrid:
            "(finishing checklist for this shape arrives in a later plan)"
        }
    }
}
