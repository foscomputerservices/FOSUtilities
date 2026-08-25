// ScrollProbeShared.swift
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

// Compiled into the app AND the UI-test bundle (project.yml lists it in both):
// presentView names the ViewModel type and ships an instance across, so both
// processes need the type.

import FOSMVVM
import Foundation

@ViewModel
struct TallCardViewModel {
    let seed: Int

    var vmId = ViewModelId()

    static func stub(seed: Int = 1) -> Self {
        .init(seed: seed)
    }
}

@ViewModel
struct BareCardViewModel {
    let seed: Int

    var vmId = ViewModelId()

    static func stub(seed: Int = 1) -> Self {
        .init(seed: seed)
    }
}

@ViewModel
struct OcclusionCardViewModel {
    let seed: Int

    var vmId = ViewModelId()

    static func stub(seed: Int = 1) -> Self {
        .init(seed: seed)
    }
}

/// Operations recorded by the occlusion card and shipped across the process boundary by
/// its transporter — the reads OcclusionScrollTests verifies could not be read at all when
/// the transporter was pruned under the scrollable wrapper.
struct OcclusionCardOps: ViewModelOperations {
    var loadCount = 0
    var setCount = 0
    var lastAmount = ""
}
