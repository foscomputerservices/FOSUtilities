// URL+Files.swift
//
// Copyright 2024 FOS Computer Services, LLC
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

public extension URL {
    /// Returns a set of **URL** for all files below the **URL** that have a given extension
    ///
    /// - Parameter ext: A file extension to match (e.g., "txt")
    func findFiles(withExtension ext: String) -> Set<URL> {
        let fileManager = FileManager.default
        var fileUrls: Set<URL> = []

        if let enumerator = fileManager.enumerator(
            at: self,
            includingPropertiesForKeys: nil
        ) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension == ext {
                fileUrls.insert(fileURL)
            }
        }

        return fileUrls
    }
}
