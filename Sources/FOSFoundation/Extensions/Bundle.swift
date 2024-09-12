// Bundle.swift
//
// Created by David Hunt on 9/11/24
// Copyright 2024 FOS Services, LLC
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

public extension Bundle {
    /// Returns **true** if the application is running in a simulator
    ///
    /// - See: [Stack Overflow](https://stackoverflow.com/a/26113597/608569)
    static var isSimulator: Bool {
        main.appStoreReceiptURL?.path.contains("CoreSimulator") ?? false
    }

    /// Returns **true** if the application was installed on the current device through *TestFlight*
    ///
    /// - See: [Stack Overflow](https://stackoverflow.com/a/26113597/608569)
    static var isTestFlightInstall: Bool {
        main.appStoreReceiptURL?.path.contains("sandboxReceipt") ?? false
    }
}
