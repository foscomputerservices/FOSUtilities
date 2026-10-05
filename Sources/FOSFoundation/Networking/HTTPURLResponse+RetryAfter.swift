// HTTPURLResponse+RetryAfter.swift
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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPURLResponse {
    /// The wait a 429 or 503 response asks for in its `Retry-After` header
    /// (RFC 9110 § 10.2.3), or `nil` when there is none to honor: another
    /// status, no header, a malformed value, or a date already past.
    func retryAfterWait(now: Date) -> Duration? {
        guard statusCode == 429 || statusCode == 503,
              let value = value(forHTTPHeaderField: "Retry-After")?
              .trimmingCharacters(in: .whitespaces),
              !value.isEmpty
        else {
            return nil
        }

        // delay-seconds = 1*DIGIT; Int(_:) alone would also accept a sign.
        if value.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return Int(value).map { .seconds($0) }
        }

        guard let date = Self.httpDate(value) else {
            return nil
        }

        let seconds = now.distance(to: date)
        return seconds > 0 ? .seconds(seconds) : nil
    }

    /// RFC 9110 § 5.6.7: recipients accept IMF-fixdate and the two obsolete forms.
    private static func httpDate(_ value: String) -> Date? {
        // asctime pads single-digit days with a space ("Nov  6").
        let collapsed = value.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")

        for format in [
            "EEE, dd MMM yyyy HH:mm:ss zzz", // IMF-fixdate
            "EEEE, dd-MMM-yy HH:mm:ss zzz", // rfc850-date
            "EEE MMM d HH:mm:ss yyyy" // asctime-date
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: collapsed) {
                return date
            }
        }

        return nil
    }
}
