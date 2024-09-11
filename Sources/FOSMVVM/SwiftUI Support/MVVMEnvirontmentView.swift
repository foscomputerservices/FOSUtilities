// MVVMEnvirontmentView.swift
//
// Created by David Hunt on 9/10/24
// Copyright 2024 FOS Services, LLC
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

#if canImport(SwiftUI)

import SwiftUI

struct MVVMEnvironmentView<Base: View>: View {
    @Environment(MVVMEnvironment.self) private var mvvmEnv
    @Environment(\.locale) private var locale
    private let baseViewFunc: (MVVMEnvironment, Locale) -> Base

    var body: some View {
        baseViewFunc(mvvmEnv, locale)
    }

    init(baseViewFunc: @escaping (MVVMEnvironment, Locale) -> Base) {
        self.baseViewFunc = baseViewFunc
    }
}

#endif