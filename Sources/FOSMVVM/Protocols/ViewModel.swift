// ViewModel.swift
//
// Created by David Hunt on 9/4/24
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

import FOSFoundation
import Foundation

/// A representation of data to present in a View
///
/// # Overview
///
/// A ``ViewModel`` contains properties and commands that are representative of how
/// a View, and in turn the user, perceives a part of the system.  The ``ViewModel``
/// translates between the application's underlying stores and the View. The translations occur
/// in the web service.
///
/// # 2-way Translation
///
/// The ``ViewModel`` is created via a ``ViewModelFactory``, which maps the data
/// stored in the application's stores to property values in the ``ViewModel``.
///
/// If the ``ViewModel`` supports modifications to the data, it provides functions to perform
/// those updates, which, in turn, use ``ServerRequest``s to communicate those changes
/// base to the web service.
///
/// # ViewModelId
///
/// A ``ViewModel`` requires a single property named ``ViewModel/vmId``.  This
/// identifier uniquely identifies the ViewModel instance.  The ``ViewModelId`` can
/// be initialized without any id and will generate a unique id randomly.  However, it is
/// recommended that an id be provided if it can reasonably be derived from the server's
/// underlying data.  For example, if the ViewModel is showing data about a user record
/// in the database, the database record id for that user could be used as the id.
///
/// ## ViewModelId and SwiftUI
///
/// ### ForEach
///
/// ``ViewModel/vmId`` is used to conform the ``ViewModel`` to the
/// [Identifiable](https://developer.apple.com/documentation/swift/identifiable)
/// protocol.  This allows ViewModel instances to be used in the
/// [ForEach](https://developer.apple.com/documentation/swiftui/foreach)
/// View when they are members of a
/// [RandomAccessCollection](https://developer.apple.com/documentation/Swift/RandomAccessCollection).
///
/// ### Swift View ID
///
/// A ``ViewModelId`` can also be used to set a SwiftUI View's [identity](https://developer.apple.com/documentation/swiftui/view/id(_:) )
public protocol ViewModel: ServerRequestBody, Stubbable {
    var vmId: ViewModelId { get }
}

public extension ViewModel where Self: Identifiable {
    var id: ViewModelId { vmId }
}
