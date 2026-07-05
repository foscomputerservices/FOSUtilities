// Request+FOS.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

import FOSFoundation
import FOSMVVM
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

public extension Request {
    // MARK: ServerRequest Support

    /// Retrieves the *ServerRequestQuery* from the Vapor Request
    ///
    /// - Parameter queryType: The concrete type of the *ServerRequestQuery*
    /// - Returns: The query from the Vapor Request's url, if any
    func serverRequestQuery<Q: ServerRequestQuery>(ofType queryType: Q.Type) throws -> Q? {
        guard queryType != EmptyQuery.self else { return nil }
        guard let rawQueryStr = serverRequestURLComponents.query else {
            return nil
        }

        guard
            let queryStr = rawQueryStr.removingPercentEncoding
        else {
            throw Abort(.badRequest)
        }

        return try queryStr.fromJSON()
    }

    /// Retrieves the *ServerRequestSort* from the Vapor Request
    ///
    /// ```swift
    /// app.get("berths") { req in
    ///     let sort = try req.serverRequestSort(ofType: SortCriteria<BerthSortKey>.self)
    ///     ...
    /// }
    /// ```
    ///
    /// - Parameter sortType: The concrete type of the *ServerRequestSort*
    /// - Returns: The sort from the Vapor Request's url, or `nil` if the request carries none
    func serverRequestSort<S: ServerRequestSort>(ofType sortType: S.Type) throws -> S? {
        guard sortType != EmptySort.self else { return nil }
        guard let rawSortStr = serverRequestURLComponents.sort else {
            return nil
        }

        guard
            let sortStr = rawSortStr.removingPercentEncoding
        else {
            throw Abort(.badRequest)
        }

        return try sortStr.fromJSON()
    }

    /// Retrieves the *ServerRequestQuery* from the Vapor Request
    ///
    /// Uses ``serverRequestQuery(ofType:)`` to retrieve the *ServerRequestQuery* from
    /// the Vapor Request.  If no query is found, throws *Abort(.badRequest*.
    ///
    /// - Parameter queryType: The concrete type of the *ServerRequestQuery*
    /// - Returns: The query from the Vapor Request's url
    /// - Throws: Abort(.badRequest) if no query was provided
    func requireServerRequestQuery<Q: ServerRequestQuery>(ofType queryType: Q.Type) throws -> Q {
        guard let query = try serverRequestQuery(ofType: queryType) else {
            throw Abort(.badRequest)
        }

        return query
    }

    // MARK: Information Retrieval

    /// Retrieves the *ServerRequestAction* from the Vapor Request
    ///
    /// The *Request*'s method and url are used to map to FOS's
    /// *ServerRequestAction*.
    ///
    /// - Throws: If the request cannot be mapped to a *ServerRequestAction*
    func requestAction() throws -> ServerRequestAction {
        try .init(httpMethod: method, uri: url)
    }

    // MARK: Compatibility

    /// Retrieves the *SystemVersion* for the Application (client) from the Vapor Request
    ///
    /// - Throws: **SystemVersionError.missingSystemVersion** if there is no value for
    ///   SystemVersion.httpHeader in Request's headers
    func applicationVersion() throws -> SystemVersion {
        guard
            let versionHeaderData = headers[SystemVersion.httpHeader].first,
            !versionHeaderData.isEmpty
        else {
            throw SystemVersionError.missingSystemVersion
        }

        return try versionHeaderData.fromJSON()
    }

    /// Require that the application's *SystemVersion*  is compatible with the server
    ///
    /// Checks the requests's headers for a *SystemVersion.systemVersioningHeader* and,
    /// if found, verifies that the SystemVersion encoded in that header's value is compatible
    /// with the server's version.
    func requireCompatibleAppVersion() throws {
        let appVersion = try applicationVersion()
        guard appVersion.isCompatible(with: .current) else {
            throw SystemVersionError.incompatibleVersion(requested: appVersion, required: .current)
        }
    }

    // MARK: Localization Support

    /// Converts the [Accept-Language](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Language)
    /// HTTP request header to a *Locale* instance
    ///
    /// - Returns: The *Locale* corresponding to the Accept-Language value or
    ///  *nil* if missing or an invalid value
    var locale: Locale? {
        var result: Locale?

        let accepts = headers[HTTPHeaders.Name.acceptLanguage]
        for lang in accepts where result == nil {
            result = Locale(identifier: lang)
        }

        return result
    }

    /// Converts the [Accept-Language](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Language)
    /// HTTP request header to a *Locale* instance
    ///
    /// - Returns: The *Locale* corresponding to the Accept-Language value
    /// - Throws: *YamlStoreError.noLocaleFound* if missing or an invalid value
    func requireLocale() throws -> Locale {
        guard let locale else {
            throw YamlStoreError.noLocaleFound
        }

        return locale
    }

    /// Returns a *JSONEncoder* instance that can localize *Localizable* instances
    /// according to the Vapor *Request*'s *Locale*
    ///
    /// This routine combines the *Request*'s [Accept-Language](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Language)
    /// setting and the *Application*'s *LocalizationStore* to provide a *JSONEncoder*
    /// that will localize JSON to the *Request*'s specification.
    ///
    /// - Throws: *YamlStoreError.noLocaleFound* or *YamlStoreError.noLocalizationStore*
    ///  if either is missing
    var localizingEncoder: JSONEncoder {
        get throws {
            try JSONEncoder.localizingEncoder(
                locale: requireLocale(),
                localizationStore: application.requireLocalizationStore()
            )
        }
    }
}

private extension Request {
    /// Splits the request URL's raw query into the legacy whole-string query blob and the
    /// reserved sort item's raw (still percent-encoded) value.
    ///
    /// Splitting on a raw "&" is safe: `URLQueryItem` percent-encodes '&' and '=' inside
    /// item names and values, so an unencoded '&' only ever separates items. "sort" is the
    /// reserved item name (see `URL.appending(serverRequest:)` in FOSMVVM); the legacy query
    /// blob rides in an item NAME as percent-encoded JSON, which can never begin with
    /// "sort=". On a hand-forged URL with multiple "sort=" components, the behavior is
    /// deliberate: first wins; all "sort=" components are peeled from the query
    /// remainder. Pinned by ServerRequestSortURLTests — never published in DocC.
    var serverRequestURLComponents: (query: String?, sort: String?) {
        guard let rawQueryStr = url.query, !rawQueryStr.isEmpty else {
            return (query: nil, sort: nil)
        }

        let sortPrefix = "sort="
        let components = rawQueryStr.components(separatedBy: "&")
        let sortValue = components
            .first { $0.hasPrefix(sortPrefix) }?
            .dropFirst(sortPrefix.count)
        let queryComponents = components.filter { !$0.hasPrefix(sortPrefix) }

        return (
            query: queryComponents.isEmpty ? nil : queryComponents.joined(separator: "&"),
            sort: sortValue.map(String.init)
        )
    }
}
