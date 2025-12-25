// Localizable+Leaf.swift
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

import FOSMVVM
import LeafKit

// Extends `Localizable` types to render as their `localizedString` in Leaf templates
//
// Without this extension, Localizable types that encode as keyed containers
// (like `LocalizableDate`) would render as their debug description instead of
// the localized string value.

// MARK: - Concrete Conformances

extension LocalizableString: LeafDataRepresentable {
    public var leafData: LeafData {
        .string((try? localizedString) ?? "")
    }
}

extension LocalizableDate: LeafDataRepresentable {
    public var leafData: LeafData {
        .string((try? localizedString) ?? "")
    }
}

extension LocalizableInt: LeafDataRepresentable {
    public var leafData: LeafData {
        .string((try? localizedString) ?? "")
    }
}

extension LocalizableArray: LeafDataRepresentable {
    public var leafData: LeafData {
        .string((try? localizedString) ?? "")
    }
}

extension LocalizableCompoundValue: LeafDataRepresentable {
    public var leafData: LeafData {
        .string((try? localizedString) ?? "")
    }
}

extension LocalizableSubstitutions: LeafDataRepresentable {
    public var leafData: LeafData {
        .string((try? localizedString) ?? "")
    }
}
