// FOSMVVMResources.swift
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

import Foundation

/// Resource bundle accessor for FOSMVVM Resources.
///
/// Provides access to Resources/React.
public enum FOSMVVMResourceAccess {
    /// The resource bundle for the ViewModels target.
    ///
    /// Use this to access ViewModel YAML localization files.
    public static let resourcesBundle: Bundle = .module
}
