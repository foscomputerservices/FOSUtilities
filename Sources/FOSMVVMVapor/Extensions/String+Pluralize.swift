// String+Pluralize.swift
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

import Foundation

extension String {
    /// Returns the plural form of the string.
    ///
    /// First checks a dictionary of known singular-to-plural mappings,
    /// then falls back to English pluralization rules for unknown words.
    ///
    /// - Returns: The pluralized form of the string
    func pluralize() -> String {
        if let mapped = Self.singularToPluralMapping[self] {
            return mapped
        }

        return pluralizeByRules()
    }

    private func pluralizeByRules() -> String {
        guard !isEmpty else { return self }

        let lowercased = self.lowercased()

        // Words ending in -s, -ss, -x, -z, -ch, -sh → add "es"
        if lowercased.hasSuffix("ss") ||
            lowercased.hasSuffix("x") ||
            lowercased.hasSuffix("z") ||
            lowercased.hasSuffix("ch") ||
            lowercased.hasSuffix("sh") {
            return self + "es"
        }

        // Words ending in consonant + y → change y to "ies"
        if lowercased.hasSuffix("y") {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
            let beforeY = lowercased.dropLast().last
            if let beforeY, !vowels.contains(beforeY) {
                return String(dropLast()) + "ies"
            }
        }

        // Words ending in -s (but not -ss, handled above) are likely already plural
        // or uncountable - just return as-is with "es" to be safe
        if lowercased.hasSuffix("s") {
            return self + "es"
        }

        // Default: add "s"
        return self + "s"
    }

    private static let singularToPluralMapping: [String: String] = [
        "user": "users",
        "customer": "customers",
        "order": "orders",
        "product": "products",
        "program": "programs",
        "account": "accounts",
        "address": "addresses",
        "company": "companies",
        "employee": "employees",
        "category": "categories",
        "item": "items",
        "transaction": "transactions",
        "payment": "payments",
        "invoice": "invoices",
        "contact": "contacts",
        "message": "messages",
        "document": "documents",
        "file": "files",
        "image": "images",
        "video": "videos",
        "comment": "comments",
        "review": "reviews",
        "rating": "ratings",
        "tag": "tags",
        "role": "roles",
        "permission": "permissions",
        "group": "groups",
        "team": "teams",
        "project": "projects",
        "task": "tasks",
        "event": "events",
        "session": "sessions",
        "log": "logs",
        "report": "reports",
        "setting": "settings",
        "configuration": "configurations",
        "template": "templates",
        "layout": "layouts",
        "page": "pages",
        "post": "posts",
        "article": "articles",
        "news": "news",
        "blog": "blogs",
        "forum": "forums",
        "thread": "threads",
        "reply": "replies",
        "notification": "notifications",
        "alert": "alerts",
        "email": "emails",
        "phone": "phones",
        "location": "locations",
        "country": "countries",
        "state": "states",
        "city": "cities",
        "region": "regions",
        "department": "departments",
        "division": "divisions",
        "branch": "branches",
        "office": "offices",
        "store": "stores",
        "warehouse": "warehouses",
        "inventory": "inventories",
        "stock": "stocks",
        "supplier": "suppliers",
        "vendor": "vendors",
        "contract": "contracts",
        "agreement": "agreements",
        "license": "licenses",
        "subscription": "subscriptions",
        "plan": "plans",
        "package": "packages",
        "service": "services",
        "feature": "features",
        "module": "modules",
        "component": "components",
        "widget": "widgets",
        "plugin": "plugins",
        "extension": "extensions",
        "application": "applications",
        "system": "systems",
        "database": "databases",
        "table": "tables",
        "column": "columns",
        "row": "rows",
        "record": "records",
        "field": "fields",
        "value": "values",
        "property": "properties",
        "attribute": "attributes",
        "parameter": "parameters",
        "variable": "variables",
        "method": "methods",
        "function": "functions",
        "procedure": "procedures",
        "query": "queries",
        "request": "requests",
        "response": "responses",
        "token": "tokens",
        "key": "keys",
        "certificate": "certificates",
        "credential": "credentials",
        "policy": "policies",
        "rule": "rules",
        "workflow": "workflows",
        "process": "processes",
        "status": "statuses",
        "priority": "priorities",
        "schedule": "schedules",
        "appointment": "appointments",
        "reservation": "reservations",
        "booking": "bookings",

        // Irregular plurals (don't follow standard rules)
        "person": "people",
        "man": "men",
        "woman": "women",
        "child": "children",
        "foot": "feet",
        "tooth": "teeth",
        "goose": "geese",
        "mouse": "mice",
        "ox": "oxen",

        // Words ending in -f/-fe that change to -ves
        "leaf": "leaves",
        "life": "lives",
        "wife": "wives",
        "knife": "knives",
        "wolf": "wolves",
        "half": "halves",
        "shelf": "shelves",
        "self": "selves",
        "calf": "calves",
        "loaf": "loaves",
        "thief": "thieves",

        // Words ending in -f that just add -s (exceptions to -ves rule)
        "roof": "roofs",
        "proof": "proofs",
        "chief": "chiefs",
        "belief": "beliefs",
        "cliff": "cliffs",
        "gulf": "gulfs",

        // Words ending in -o that add -es
        "hero": "heroes",
        "potato": "potatoes",
        "tomato": "tomatoes",
        "echo": "echoes",
        "veto": "vetoes",

        // Latin/Greek plurals commonly used in tech/science
        "datum": "data",
        "criterion": "criteria",
        "phenomenon": "phenomena",
        "analysis": "analyses",
        "basis": "bases",
        "crisis": "crises",
        "thesis": "theses",
        "hypothesis": "hypotheses",
        "diagnosis": "diagnoses",
        "index": "indices",
        "appendix": "appendices",
        "matrix": "matrices",
        "vertex": "vertices",
        "axis": "axes",
        "focus": "foci",
        "radius": "radii",
        "stimulus": "stimuli",
        "curriculum": "curricula",
        "medium": "media",
        "memorandum": "memoranda",
        "schema": "schemas",
        "antenna": "antennae",
        "formula": "formulae",

        // Uncountable nouns (same singular and plural)
        "information": "information",
        "equipment": "equipment",
        "furniture": "furniture",
        "software": "software",
        "hardware": "hardware",
        "feedback": "feedback",
        "advice": "advice",
        "knowledge": "knowledge",
        "research": "research",
        "traffic": "traffic",
        "money": "money",
        "music": "music",
        "data": "data",
        "sheep": "sheep",
        "fish": "fish",
        "deer": "deer",
        "species": "species",
        "series": "series",
        "aircraft": "aircraft",
        "offspring": "offspring",
        "moose": "moose"
    ]
}
