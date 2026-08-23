import FOSMVVMBootstrap
import Testing

@Suite struct SmokeTests {
    @Test func versionExists() {
        #expect(!Release.version.isEmpty)
    }
}
