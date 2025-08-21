#if os(Android) || os(Linux)

// Swift Standard Library Workaround
//
// This fixes the following linker error:
// error: link command failed with exit code 1 (use -v to see invocation)
// /usr/lib/swift/linux/libswiftObservation.so: error: undefined reference to 'swift::threading::fatal(char const*, ...)'
// clang: error: linker command failed with exit code 1 (use -v to see invocation)
// [2908/3111] Linking accel-sharpPackageTests.xctest
//
// Here's the open PR: https://github.com/swiftlang/swift/pull/77890
@_cdecl("_ZN5swift9threading5fatalEPKcz")
func swiftThreadingFatal() {}
#endif