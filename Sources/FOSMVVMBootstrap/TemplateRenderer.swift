// TemplateRenderer.swift
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

// TemplateRenderer.swift
import Foundation

public enum TemplateError: Error, Equatable {
    case unrenderedToken(token: String, context: String)
}

/// Strict `{{TOKEN}}` substitution. No logic, no loops, no filters —
/// derivation happens in typed Swift (TokenSet), never in templates.
/// Any token left unrendered is a fatal error: the tool must never
/// emit a file containing `{{`.
public enum TemplateRenderer {
    /// Substitutes every `{{TOKEN}}` in `content` with its value:
    /// `try TemplateRenderer.render(content: "hi {{NAME}}", tokens: ["NAME": "Sam"]) // "hi Sam"`.
    ///
    /// Throws `TemplateError.unrenderedToken` if any `{{TOKEN}}` remains
    /// after substitution — a generated file must never contain `{{`.
    public static func render(content: String, tokens: [String: String]) throws -> String {
        var out = content
        for (key, value) in tokens {
            out = out.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        if let range = out.range(of: #"\{\{[A-Z0-9_]+\}\}"#, options: .regularExpression) {
            let token = String(out[range])
            let lineRange = out.lineRange(for: range)
            let context = out[lineRange].trimmingCharacters(in: .whitespacesAndNewlines)
            throw TemplateError.unrenderedToken(token: token, context: context)
        }
        return out
    }

    /// Renders a template path, then drops a trailing `.tmpl`:
    /// `try TemplateRenderer.render(relativePath: "Sources/{{NAME}}/App.swift.tmpl", tokens: ["NAME": "Sam"]) // "Sources/Sam/App.swift"`.
    ///
    /// Throws `TemplateError.unrenderedToken` if any `{{TOKEN}}` remains
    /// in the path after substitution.
    public static func render(relativePath: String, tokens: [String: String]) throws -> String {
        var path = try render(content: relativePath, tokens: tokens)
        if path.hasSuffix(".tmpl") {
            path = String(path.dropLast(".tmpl".count))
        }
        return path
    }
}
