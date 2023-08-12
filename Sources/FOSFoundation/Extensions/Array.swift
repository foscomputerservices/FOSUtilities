// Array.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

public extension Array {
    static func + (lhs: [Element], rhs: [Element]?) {
        guard let rhs else { return }

        return lhs + rhs
    }

    static func += (lhs: inout [Element], rhs: [Element]?) {
        guard let rhs else { return }

        return lhs += rhs
    }
}
