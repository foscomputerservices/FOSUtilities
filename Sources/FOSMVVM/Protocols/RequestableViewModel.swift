// RequestableViewModel.swift
//
// Created by David Hunt on 9/11/24
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

/// Indicates that a ``ViewModel`` is directly requestable from the
/// web service via a ``RequestableViewModel/Request``
///
/// ## Example
///
/// ```swift
/// public struct LandingPageViewModel: RequestableViewModel {
///   public typealias Request = LandingPageRequest
///
///   @LocalizedString public var pageTitle
///
///   public var vmId = ViewModelId()
///
///   public init() {}
/// }
/// ```
public protocol RequestableViewModel: ViewModel {
    /// The ``ViewModelRequest`` that will be used to request
    /// instances of ``ViewModel`` from the web service
    associatedtype Request: ViewModelRequest
}
