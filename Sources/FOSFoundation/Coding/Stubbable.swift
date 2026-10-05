// Stubbable.swift
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

/// A type that can hand tests and previews a fully valid sample instance.
///
/// Declare a `stub(...)` overload whose every parameter has a default and that calls `init`, then
/// forward the parameterless `stub()` to it. A parameter for a child may instead be the value that
/// chains down into the child's `stub(...)` (see below):
///
/// ```swift
/// struct CardViewModel: Stubbable {
///     let title: String
///     let position: Int
///
///     static func stub(title: String = "Card", position: Int = 0) -> Self {
///         .init(title: title, position: position)
///     }
///
///     static func stub() -> Self {
///         .stub(title: "Card")
///     }
/// }
///
/// let anyCard = CardViewModel.stub()
/// let titled = CardViewModel.stub(title: "Ship it")
/// let third = CardViewModel.stub(position: 2)
/// ```
///
/// A test or preview names only the one detail it cares about and still receives a fully valid
/// instance, however many levels deep the type is.
///
/// `stub()` must pass at least one argument explicitly. With none, `.stub()` resolves to itself
/// and recurses forever; it doesn't matter which argument you pick.
///
/// ## Chaining into children
///
/// When a value passed at the top belongs to the children too, forward it to their `stub(...)`
/// so the whole hierarchy stays valid and consistent:
///
/// ```swift
/// struct BoardViewModel: Stubbable {
///     let cardList: CardListViewModel
///
///     static func stub(number: Int = 0) -> Self {
///         .init(cardList: .stub(number: number))
///     }
///
///     static func stub() -> Self {
///         .stub(number: 0)
///     }
/// }
///
/// struct CardListViewModel: Stubbable {
///     let number: Int
///
///     static func stub(number: Int = 0) -> Self {
///         .init(number: number)
///     }
///
///     static func stub() -> Self {
///         .stub(number: 0)
///     }
/// }
///
/// let board = BoardViewModel.stub(number: 7)   // board.cardList.number == 7
/// ```
///
/// > A type with no init parameters to vary, such as an opaque identity, has only `stub()`.
public protocol Stubbable {
    static func stub() -> Self
}
