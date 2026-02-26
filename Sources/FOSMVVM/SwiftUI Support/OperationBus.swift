//
//  OperationBus.swift
//  FOSUtilities
//
//  Created by David Hunt on 2/26/26.
//

import FOSFoundation
import Foundation

/// A type-safe synchronous operation bus that manages and invokes a collection of operations.
///
/// `SyncOperationBus` provides a simple publish-subscribe pattern where multiple operations
/// can be registered to respond to a single invocation. This is useful for decoupling
/// components that need to react to events or data changes.
///
/// All operations are executed synchronously on the calling thread in the order they were registered.
///
/// ## Basic Usage Example
///
/// ```swift
/// // Create a bus for string operations
/// let bus = SyncOperationBus<String>()
///
/// // Register operations
/// bus.addOperation { message in
///     print("Handler 1: \(message)")
/// }
///
/// bus.addOperation { message in
///     print("Handler 2: \(message)")
/// }
///
/// // Invoke all registered operations
/// bus.invoke("Hello, World!")
/// // Output:
/// // Handler 1: Hello, World!
/// // Handler 2: Hello, World!
/// ```
///
/// ## ViewModelView Form Coordination Example
///
/// A common pattern is using `SyncOperationBus` to coordinate data collection between a parent
/// `ViewModelView` and multiple child `ViewModelView`s in a complex form:
///
/// ```swift
/// // Shared mutable data structure
/// struct FormData {
///     var personalInfo: PersonalInfo?
///     var addressInfo: AddressInfo?
///     var preferences: Preferences?
/// }
///
/// // Parent ViewModelView
/// struct ParentFormView: View {
///     @State private var saveBus = SyncOperationBus<FormData>()
///
///     var body: some View {
///         VStack {
///             PersonalInfoView(saveBus: saveBus)
///             AddressView(saveBus: saveBus)
///             PreferencesView(saveBus: saveBus)
///
///             Button("Save") {
///                 var formData = FormData()
///                 saveBus.invoke(&formData)  // Each child updates formData
///                 submitForm(formData)
///             }
///         }
///     }
/// }
///
/// // Child ViewModelView
/// struct PersonalInfoView: View {
///     let saveBus: SyncOperationBus<FormData>
///     @State private var name: String = ""
///     @State private var email: String = ""
///
///     var body: some View {
///         VStack {
///             TextField("Name", text: $name)
///             TextField("Email", text: $email)
///         }
///         .onAppear {
///             saveBus.addOperation { formData in
///                 formData.personalInfo = PersonalInfo(name: name, email: email)
///             }
///         }
///     }
/// }
/// ```
///
/// - Note: Operations are invoked in the order they were registered.
/// - Important: All operations are executed synchronously on the calling thread.
///
/// For asynchronous operations, see ``AsyncOperationBus``.
public final class SyncOperationBus<A> {
    /// The collection of registered operations.
    private var operations: [(inout A) -> Void]

    /// Registers a new operation to be invoked when `invoke(_:)` is called.
    ///
    /// Operations are stored and invoked in the order they are added.
    ///
    /// - Parameter operation: A closure that accepts an `inout` parameter of type `A`.
    ///   The closure can read or mutate the value. The closure is marked as `@escaping`
    ///   because it is stored for later execution.
    ///
    /// ## Example (Read-Only)
    ///
    /// ```swift
    /// let bus = SyncOperationBus<Int>()
    /// bus.addOperation { value in
    ///     print("Received: \(value)")
    /// }
    /// ```
    ///
    /// ## Example (Mutating)
    ///
    /// ```swift
    /// struct FormData {
    ///     var name: String = ""
    /// }
    ///
    /// let bus = SyncOperationBus<FormData>()
    /// bus.addOperation { formData in
    ///     formData.name = "Alice"
    /// }
    ///
    /// var data = FormData()
    /// bus.invoke(&data)
    /// print(data.name) // Prints "Alice"
    /// ```
    public func addOperation(_ operation: @escaping (inout A) -> Void) {
        operations.append(operation)
    }

    /// Invokes all registered operations with the provided mutable value.
    ///
    /// All operations are executed synchronously in the order they were registered.
    /// Each operation can read or mutate the value, and subsequent operations will see the changes.
    ///
    /// - Parameter value: The mutable value to pass to each registered operation.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct FormData {
    ///     var count: Int = 0
    /// }
    ///
    /// let bus = SyncOperationBus<FormData>()
    /// bus.addOperation { formData in
    ///     formData.count += 1
    /// }
    /// bus.addOperation { formData in
    ///     formData.count += 2
    /// }
    ///
    /// var data = FormData()
    /// bus.invoke(&data)
    /// print(data.count) // Prints 3
    /// ```
    public func invoke(_ value: inout A) {
        operations.forEach { $0(&value) }
    }

    /// Creates a new, empty synchronous operation bus.
    ///
    /// The bus is initialized with no registered operations. Use `addOperation(_:)`
    /// to register operations that will be invoked when `invoke(_:)` is called.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let bus = SyncOperationBus<String>()
    /// ```
    public init() {
        operations = []
    }
}

/// A type-safe asynchronous operation bus that manages and invokes a collection of async operations.
///
/// `AsyncOperationBus` provides a publish-subscribe pattern for asynchronous operations where
/// multiple async operations can be registered and invoked concurrently. This is useful for
/// decoupling components that need to react to events or data changes asynchronously.
///
/// All operations are executed concurrently using Swift's structured concurrency (task groups).
///
/// ## Basic Usage Example
///
/// ```swift
/// let bus = AsyncOperationBus<String>()
///
/// // Register async operations
/// bus.addOperation { message in
///     try await Task.sleep(for: .seconds(1))
///     print("Handler 1: \(message)")
/// }
///
/// bus.addOperation { message in
///     try await Task.sleep(for: .seconds(1))
///     print("Handler 2: \(message)")
/// }
///
/// // Invoke all operations (executes concurrently)
/// await bus.invoke("Hello, Async!")
/// // Both handlers execute concurrently and complete in ~1 second
/// ```
///
/// ## ViewModelView Form Coordination Example
///
/// A common pattern is using `AsyncOperationBus` to coordinate asynchronous data validation and
/// submission between a parent `ViewModelView` and multiple child `ViewModelView`s in a complex form:
///
/// ```swift
/// // Shared mutable data structure (must be Sendable)
/// final class FormData: Sendable {
///     let personalInfo = Mutex<PersonalInfo?>(nil)
///     let addressInfo = Mutex<AddressInfo?>(nil)
///     let preferences = Mutex<Preferences?>(nil)
/// }
///
/// // Parent ViewModelView
/// struct ParentFormView: View {
///     @State private var saveBus = AsyncOperationBus<FormData>()
///
///     var body: some View {
///         VStack {
///             PersonalInfoView(saveBus: saveBus)
///             AddressView(saveBus: saveBus)
///             PreferencesView(saveBus: saveBus)
///
///             Button("Save") {
///                 Task {
///                     let formData = FormData()
///                     await saveBus.invoke(formData)  // All children validate & update concurrently
///                     await submitForm(formData)
///                 }
///             }
///         }
///     }
/// }
///
/// // Child ViewModelView
/// struct PersonalInfoView: View {
///     let saveBus: AsyncOperationBus<FormData>
///     @State private var name: String = ""
///     @State private var email: String = ""
///
///     var body: some View {
///         VStack {
///             TextField("Name", text: $name)
///             TextField("Email", text: $email)
///         }
///         .onAppear {
///             saveBus.addOperation { formData in
///                 // Perform async validation
///                 let isValid = await validateEmail(email)
///                 guard isValid else { return }
///
///                 // Update shared data
///                 formData.personalInfo.withLock { info in
///                     info = PersonalInfo(name: name, email: email)
///                 }
///             }
///         }
///     }
/// }
/// ```
///
/// - Note: Operations are registered in order but execute concurrently when invoked.
/// - Important: The `invoke(_:)` method waits for all operations to complete before returning.
/// - Important: The generic parameter `A` must conform to `Sendable` for thread-safe concurrent execution.
/// - Important: When using mutable shared data, ensure thread-safe access (e.g., using `Mutex` or actor isolation).
///
/// For synchronous operations, see ``SyncOperationBus``.
public final class AsyncOperationBus<A: Sendable>: @unchecked Sendable {
    /// The collection of registered asynchronous operations.
    private var operations: [@Sendable (A) async -> Void]

    /// Registers a new asynchronous operation to be invoked when `invoke(_:)` is called.
    ///
    /// Operations are stored in the order they are added, but execute concurrently
    /// when invoked via `invoke(_:)`.
    ///
    /// - Parameter operation: An async closure that accepts a value of type `A`.
    ///   The closure is marked as `@escaping` and `@Sendable` because it is stored
    ///   for later concurrent execution.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let bus = AsyncOperationBus<String>()
    /// bus.addOperation { message in
    ///     try await Task.sleep(for: .seconds(1))
    ///     print("Async: \(message)")
    /// }
    /// ```
    public func addOperation(_ operation: @escaping @Sendable (A) async -> Void) {
        operations.append(operation)
    }

    /// Invokes all registered asynchronous operations with the provided value.
    ///
    /// All operations are executed concurrently using a task group. This method
    /// waits for all operations to complete before returning.
    ///
    /// - Parameter value: The value to pass to each registered operation.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let bus = AsyncOperationBus<String>()
    /// bus.addOperation { message in
    ///     try await Task.sleep(for: .seconds(1))
    ///     print("Handler 1: \(message)")
    /// }
    /// bus.addOperation { message in
    ///     try await Task.sleep(for: .seconds(1))
    ///     print("Handler 2: \(message)")
    /// }
    /// await bus.invoke("Test")
    /// // Both handlers execute concurrently and complete in ~1 second
    /// ```
    public func invoke(_ value: A) async {
        let operations = operations
        await withTaskGroup(of: Void.self) { group in
            for operation in operations {
                group.addTask {
                    await operation(value)
                }
            }
        }
    }

    /// Creates a new, empty asynchronous operation bus.
    ///
    /// The bus is initialized with no registered operations. Use `addOperation(_:)`
    /// to register async operations that will be invoked concurrently when `invoke(_:)` is called.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let bus = AsyncOperationBus<String>()
    /// ```
    public init() {
        operations = []
    }
}
