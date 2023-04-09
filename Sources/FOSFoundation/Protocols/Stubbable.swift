// Stubbable.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

/// Returns an instance that can be used for testing purposes
public protocol Stubbable {
    static func stub() -> Self
}
