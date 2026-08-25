// Release.swift
//
// Copyright 2026 FOS Computer Services, LLC
//
// Licensed under the Apache License, Version 2.0 (the  License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// The FOSUtilities release this scaffolder ships with.
///
/// Generated projects pin FOSUtilities `from:` this version, and the CLI reports
/// it as its own version — the scaffolder and the framework release together.
///
/// RELEASE RITUAL: the CHANGELOG stamp commit updates this constant. The
/// release-stamp test in FOSMVVMBootstrapTests compares it against the topmost
/// stamped CHANGELOG release and fails CI when they disagree.
public enum Release {
    public static let version = "0.15.0"
}
