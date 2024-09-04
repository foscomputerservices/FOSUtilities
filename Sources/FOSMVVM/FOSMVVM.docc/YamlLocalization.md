# Getting Started With YAML and Localization

Organize localized strings in YAML files.

## Overview

The default Localization model uses [YAML](https://yaml.org/) files to store the localized strings.
YAML provides a very rich set of primitives for organizing data.  The ``LocalizableRef`` enum
provides a set of standardized APIs for simplifying the management of an application's YAML
files and for simplifying the mapping of the data in the files to the various M-V-VM components.

> It is very important to note that **all** .yml files in the application will be merged together into a single
> dictionary.  The system automatically merges the Locales, however collisions of keys at the levels below
> the Locale will result in warnings being written to the log and the final mapping result is considered undefined.

## Locale Specification

The top key in any YAML file should be the 'Locale' identifier.  Smart matching is performed so that
the region and script codes may be omitted if they are not needed.  Additionally, the locale string
lookup is case *insensitive*.

### Region Agnostic Specification
```
en:
    text: 'Some Text'
es:
    text: 'Algún texto'
```

### Region Specific Specification
```
en-us:
    carFrontCover: 'Hood'
en-gb:
    carFrontCover: 'Bonnet'
```

## View-Model Property Binding

`LocalizableRef` has direct support for binding between a View-Model's property and its YAML value

To use this mechanism, the top key under the Locale key must correspond exactly to the Swift type of the View-Model.

For the following examples, we will use the following YAML:

```yaml
en:
  MyViewModel:
    property: "This is the localized string!"
```

Each of the following examples accomplishes the same task, just with different supported mechanisms.


## Preferred Example: ViewModel and Property Wrapper

```swift
struct MyViewModel: ViewModel {
   @I18nProperty("property") let property

   init() { }
}
```

### Alternative Example: Manual Binding

``` swift
struct MyViewModel {
   let property: LocalizableString

   init() {
     self.property = .localized(.init(for: Self.self, propertyName: "property"))
   }
}
```

### Alternative Example: Property Field Wrapper

```swift
struct MyViewModel {
   @I18nPropertyField<MyType, LocalizableString>("property") let property: LocalizableString

   init() { }
}
```

- NOTE: If the View-Model is a generic type, the final type will be stripped of its
         generic substitution and only the base type name will
         be used as the key name.  (i.e., `MyGenericViewModel<T>` will become `MyGenericViewModel`).
         Please note that this means that localization using @I18nProperty **cannot** be bound based
         on the Generic type substitution ('T').  If that is required, one of the other mechanisms must
         be used.

### Nested Type Support

In some situations View-Models contain nested types that need their properties bound.  The *parentType* parameter
provides support for these situations.  Consider the following View-Model:

```swift
struct ParentViewModel: ViewModel {
  enum NestedEnum: String {
     case option1
     case option2

     var display: LocalizableString {
         .localized(.init(for: Self.self, parentType: ParentViewModel.self, propertyName: rawValue))
     }
  }
}
```

```yaml
  en:
    ParentViewModel:
      NestedEnum:
        option1: "Option #1"
        option2: "Option #2"
```

### Multiple Value support

At times there are situations where having multiple values associated with a property can be handy.  For these cases,
there are two ways to identify such values: **Key Discriminator**s and **Index Discriminator**s.

#### Key Discriminator

A key discriminator expects a dictionary under the property name key in the YAML.

##### Example

```swift
struct UserViewModel: ViewModel {
     @I18nProperty("property", discriminatorKey: "shortTitle") let shortTitle
     @I18nProperty("property", discriminatorKey: "longTitle") let longTitle
     @I18nProperty("property", discriminatorKey: "display") let property
}
```

```yaml
  en:
    UserViewModel:
      property:
        shortTitle: "Short"
        longTitle: "A Very Long Title"
        display: "Property"
```

#### Index Discriminator

An index discriminator expects an array under the property name key in the YAML.

##### Example

```swift
struct UserViewModel: ViewModel {
     @I18nProperty("property", discriminatorIndex: 0) let shortTitle
     @I18nProperty("property", discriminatorIndex: 1) let longTitle
     @I18nProperty("property", discriminatorIndex: 2) let property
}
```

```yaml
  en:
    UserViewModel:
      property:
        - "Option #1"
        - "Option #2"
        - "Option #3"
```
