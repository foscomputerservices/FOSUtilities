// TestTags.swift
//
// Created by David Hunt on 8/22/24
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

import Testing

extension Tag {
    @Tag static var extensions: Self
    @Tag static var string: Self
    @Tag static var json: Self
    @Tag static var async: Self
    @Tag static var networking: Self
}