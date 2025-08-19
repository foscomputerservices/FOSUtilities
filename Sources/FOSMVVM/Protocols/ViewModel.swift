// ViewModel.swift
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
/// # Conformance
///
/// Conforming to ``ViewModel`` indicates to the system that the type is a **View-Model**
/// in the **M-V-VM** architecture.
///
/// # Supporting @ViewModel Macro
///
/// Applying the protocol by itself to a type will require the implementation to
/// provide the ``propertyNames()`` bindings manually.  Instead, of adding
/// ``ViewModel`` as conformance, always use the @``ViewModel()``
/// macro, which will automatically generate the ``propertyNames()`` bindings.
///
/// ```swift
/// @ViewModel struct MyViewModel {
///   @LocalizedString public var aProperty
///
///   var vmId: ViewModelId = .init()
/// }
/// ```
///
/// # 2-way Communication
///
/// The ``ViewModel`` is created via a ``ViewModelFactory``, which maps the data
/// stored in the application's stores to property values in the ``ViewModel``.
///
/// If the ``ViewModel`` supports modifications to the data, it provides functions via
/// ``ViewModelOperations`` to perform those updates, which, in turn, use
/// ``ServerRequest``s to communicate those changes base to the web service.
///
/// # ViewModelId
///
/// A ``ViewModel`` requires a single property named ``ViewModel/vmId``.  This
/// identifier uniquely identifies the ViewModel instance.  The ``ViewModelId`` can
/// be initialized without any id and will generate a unique id randomly.  However, it is
/// recommended that an id be provided if it can reasonably be derived from the server's
/// underlying data.  For example, if the ViewModel is showing data about a user model
/// in the database, the database model id for that user could be used as the id.
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
///
/// ```swift
/// struct MyView: ViewModelView {
///    let viewModel: MyViewModel
///
///    var body: some View {
///      Text(viewModel.aProperty)
///        .id(viewModel.id)
///    }
/// }
/// ```
///
/// Whenever possible, the ``ViewModelId`` should be bound to some identifying characteristic
/// of the data that was used to project the ``ViewModel``.  This will greatly stabilize the
/// SwiftUI View hierarchy and caching structure.
///
/// ```swift
/// @ViewModel struct UserViewModel {
///   public let firstName: String
///   public let lastName: String
///
///   let vmId: ViewModelId
///
///   public init(user: User) {
///     self.firstName = user.firstName
///     self.lastName = user.lastName
///     self.vmId = .init(id: user.id)
///   }
/// }
/// ```
public protocol ViewModel: ServerRequestBody, RetrievablePropertyNames, Identifiable, Stubbable {
    var vmId: ViewModelId { get }
}

public extension ViewModel {
    var id: ViewModelId { vmId }
}
