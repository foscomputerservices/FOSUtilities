// Collection.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

public extension Collection {
    // Credit: https://medium.com/ios-os-x-development/little-snippet-group-by-in-swift-3-5be0a06307db
    func grouped<T>(by criteria: (Element) -> T) -> [T: [Element]] {
        var groups = [T: [Element]]()
        for element in self {
            let key = criteria(element)
            if groups.index(forKey: key) == nil {
                groups[key] = [Element]()
            }
            groups[key]?.append(element)
        }
        return groups
    }
}
