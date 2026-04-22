# Getting Started With Testing FOSMVVM

Quickly test your ``ViewModel``s and SwiftUI Views.

## Overview

FOSMVVM splits testing into two complementary tracks that match how the framework
itself is structured:

- **ViewModel tests** verify the data snapshot — localization, codable round-trip,
  version stability. These tests run outside any UI host using
  [swift-testing](https://github.com/swiftlang/swift-testing.git).
- **View tests** verify how a SwiftUI View renders a ``ViewModel`` and (for interactive
  Views) how user actions dispatch to ``ViewModelOperations``. These tests use
  [XCTest](https://developer.apple.com/documentation/xctest) and
  [XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation) against an
  actual application bundle.

The two tracks are independent; most projects want both.

## Interactive vs Display-Only Views

When writing View tests, first identify whether the View is *interactive* (has
buttons, forms, toggles — and therefore a companion ``ViewModelOperations``
implementation) or *display-only* (renders data with no user actions). The two cases
use different test base classes:

| View kind | Base class | Generic parameters |
| :-------- | :--------- | :----------------- |
| Display-only | `ViewModelDisplayTestCase<VM>` | One (the ``ViewModel``) |
| Interactive | `ViewModelViewTestCase<VM, VMO>` | Two (the ``ViewModel`` and the ``ViewModelOperations`` stub) |

Do not invent an empty ``ViewModelOperations`` protocol for a display-only View. The
display-only path was designed specifically so display-only tests need no Operations
type at all.

## Topics

- <doc:Operations>
