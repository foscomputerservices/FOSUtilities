# FOSMVVM React Utilities

JavaScript utilities for building React applications with FOSMVVM architecture.

## Overview

These utilities enable React components to consume ViewModels via WebAssembly (or HTTP fallback), mirroring SwiftUI's `ViewModelView.bind()` pattern.

## Files

| File | Purpose |
|------|---------|
| `viewModelComponent.js` | Wraps React components to add `.bind()` method |
| `fosmvvmWasmRuntime.js` | Provides `window.wasm.processRequest()` for JavaScript → Swift communication |

## Usage

### 1. Load Utilities

```html
<script type="module" src="/fosmvvm/react/fosmvvmWasmRuntime.js"></script>
<script type="module" src="/fosmvvm/react/viewModelComponent.js"></script>
```

### 2. Initialize FOSMVVM WASM Runtime

After loading your WASM module:

```javascript
import { initializeFOSMVVMWasmRuntime } from '/fosmvvm/react/fosmvvmWasmRuntime.js';

// Load your WASM module
const wasmModule = await loadYourWasmModule();

// Initialize FOSMVVM WASM Runtime
initializeFOSMVVMWasmRuntime(wasmModule);
```

Or use HTTP fallback:

```javascript
import { initializeHttpWasmRuntime } from '/fosmvvm/react/fosmvvmWasmRuntime.js';

initializeHttpWasmRuntime('https://api.example.com');
```

### 3. Create ViewModelComponent

```jsx
import { viewModelComponent } from '/fosmvvm/react/viewModelComponent.js';

const TaskList = viewModelComponent(({ viewModel }) => {
    // Handle error ViewModels
    if (viewModel.errorType === 'NotFoundError') {
        return <div className="error">{viewModel.message}</div>;
    }

    // Render success ViewModel
    return (
        <div>
            <h2>{viewModel.title}</h2>
            {viewModel.tasks.map(task => (
                <div key={task.id}>{task.title}</div>
            ))}
        </div>
    );
});

export default TaskList;
```

### 4. Use .bind() Pattern

```jsx
// Parent component
function Dashboard() {
    return (
        <div>
            <TaskList.bind
                requestType="GetTasksRequest"
                params={{ status: 'active' }}
            />
        </div>
    );
}
```

## API Reference

### fosmvvmWasmRuntime.js

#### `initializeFOSMVVMWasmRuntime(wasm)`

Initialize FOSMVVM WASM Runtime with loaded WASM module.

**Parameters:**
- `wasm` - WASM module instance that exports `processRequest(requestType, paramsJSON)` function

**Throws:**
- `Error` if WASM instance doesn't have required `processRequest` function

**Example:**
```javascript
import { initializeFOSMVVMWasmRuntime } from '/fosmvvm/react/fosmvvmWasmRuntime.js';

const wasm = await loadWasmModule();
initializeFOSMVVMWasmRuntime(wasm);
```

#### `initializeHttpWasmRuntime(baseURL)`

Initialize HTTP fallback bridge for environments without WASM support.

**Parameters:**
- `baseURL` - Base URL for ServerRequest endpoints (e.g., `"https://api.example.com"`)

**Example:**
```javascript
import { initializeHttpWasmRuntime } from '/fosmvvm/react/fosmvvmWasmRuntime.js';

initializeHttpWasmRuntime('https://api.example.com');
```

#### `window.wasm.processRequest(requestType, params)`

Process a ServerRequest via WASM or HTTP bridge.

**Parameters:**
- `requestType` (string) - ServerRequest type name (e.g., `"GetTasksRequest"`)
- `params` (object) - Request parameters (query, fragment, or body)

**Returns:** `Promise<Object>` - Resolves with ViewModel (success or domain error)

**Throws:**
- `WasmRuntimeConnectionError` - WASM bridge not initialized
- `WasmRuntimeError` - WASM function execution failed
- `NetworkError` - HTTP request failed (HTTP bridge only)

**Example:**
```javascript
const viewModel = await window.wasm.processRequest('GetTasksRequest', {
    status: 'active'
});
```

#### Error Classes

**`WasmRuntimeConnectionError`**
Thrown when WASM module is not loaded or connection failed.

**`WasmRuntimeError`**
Thrown when WASM function execution fails. Contains `originalError` property.

**`NetworkError`**
Thrown when HTTP request fails (HTTP bridge only). Contains `status` property.

### viewModelComponent.js

#### `viewModelComponent(Component, options)`

Wraps a React component to add `.bind()` method.

**Parameters:**
- `Component` (React.Component) - Component that receives `{ viewModel }` prop
- `options` (object) - Configuration options
  - `LoadingView` (React.Component) - Custom loading component
  - `ErrorView` (React.Component) - Custom error component for infrastructure errors

**Returns:** Wrapped component with `.bind()` method

**Example:**
```javascript
import { viewModelComponent } from '/fosmvvm/react/viewModelComponent.js';

const TaskList = viewModelComponent(({ viewModel }) => {
    return <div>{viewModel.title}</div>;
});
```

#### `.bind({ requestType, params, ...otherProps })`

Create a bound instance of the component that fetches its ViewModel.

**Parameters:**
- `requestType` (string) - ServerRequest type name
- `params` (object) - Request parameters
- `...otherProps` - Additional props to pass to component

**Returns:** React component instance

**Example:**
```jsx
<TaskList.bind
    requestType="GetTasksRequest"
    params={{ status: 'active' }}
    className="custom-class"
/>
```

#### `configureViewModelComponent(config)`

Configure custom loading and error views globally.

**Parameters:**
- `config` (object)
  - `LoadingView` (React.Component) - Custom loading component
  - `ErrorView` (React.Component) - Custom error component

**Example:**
```javascript
import { configureViewModelComponent } from '/fosmvvm/react/viewModelComponent.js';

configureViewModelComponent({
    LoadingView: MyCustomLoadingView,
    ErrorView: MyCustomErrorView
});
```

#### `preloadViewModel(requestType, params)`

Preload a ViewModel without rendering (useful for caching).

**Parameters:**
- `requestType` (string) - ServerRequest type name
- `params` (object) - Request parameters

**Returns:** `Promise<Object>` - Resolves with ViewModel

**Example:**
```javascript
import { preloadViewModel } from '/fosmvvm/react/viewModelComponent.js';

// Preload before navigation
await preloadViewModel('GetTaskRequest', { id: taskId });
```

## Error Handling

### Infrastructure Errors vs Domain Errors

**Infrastructure errors** are thrown as JavaScript exceptions:
- `WasmRuntimeConnectionError` - WASM not initialized
- `WasmRuntimeError` - WASM function crashed
- `NetworkError` - HTTP request failed

These are caught by `viewModelComponent` and shown with `ErrorView`.

**Domain errors** are returned as ViewModels:
- `NotFoundViewModel` - Resource not found
- `ValidationErrorViewModel` - Validation failed
- Other error-specific ViewModels

Domain errors flow through to your component - you handle them like any other ViewModel.

### Example

```jsx
const TaskCard = viewModelComponent(({ viewModel }) => {
    // Handle domain errors as ViewModels
    if (viewModel.errorType === 'NotFoundError') {
        return (
            <div className="error">
                <h3>{viewModel.errorTitle}</h3>
                <p>{viewModel.errorMessage}</p>
            </div>
        );
    }

    if (viewModel.errorType === 'ValidationError') {
        return (
            <div className="validation-error">
                <h3>{viewModel.errorTitle}</h3>
                <ul>
                    {viewModel.validationErrors.map(err => (
                        <li key={err.field}>{err.message}</li>
                    ))}
                </ul>
            </div>
        );
    }

    // Render success ViewModel
    return <div>{viewModel.title}</div>;
});
```

## Vapor Integration

### Serving Files

```swift
// In your Vapor app's configure.swift
import Vapor
import FOSMVVM

func configure(_ app: Application) throws {
    // Serve FOSMVVM React utilities
    app.middleware.use(FileMiddleware(
        bundle: Bundle.module,  // FOSUtilities bundle
        publicDirectory: app.directory.resourcesDirectory,
        servePath: "/fosmvvm/react"
    ))
}
```

### HTML Template

```html
<!DOCTYPE html>
<html>
<head>
    <title>My FOSMVVM App</title>
</head>
<body>
    <div id="root"></div>

    <!-- Load FOSMVVM utilities -->
    <script type="module" src="/fosmvvm/react/fosmvvmWasmRuntime.js"></script>
    <script type="module" src="/fosmvvm/react/viewModelComponent.js"></script>

    <!-- Load your WASM module -->
    <script type="module">
        import { initializeFOSMVVMWasmRuntime } from '/fosmvvm/react/fosmvvmWasmRuntime.js';

        // Load WASM
        const wasm = await loadYourWasmModule();
        initializeFOSMVVMWasmRuntime(wasm);

        // Now render your React app
        // ...
    </script>
</body>
</html>
```

## Browser Compatibility

- ES6 modules (import/export)
- Async/await
- Promise
- React 16.8+ (hooks)
- No build step required

## Architecture Patterns

### Pattern: Views Render Data, Don't Shape It

```jsx
// ❌ BAD - Component is transforming data
const UserCard = viewModelComponent(({ viewModel }) => {
    return <div>{viewModel.firstName} {viewModel.lastName}</div>;
});

// ✅ GOOD - ViewModel provides shaped result
const UserCard = viewModelComponent(({ viewModel }) => {
    return <div>{viewModel.fullName}</div>;
});
```

### Pattern: No fetch() Calls

```jsx
// ❌ BAD - Component making HTTP requests
const TaskList = viewModelComponent(({ viewModel }) => {
    const [data, setData] = useState([]);

    useEffect(() => {
        fetch('/api/tasks').then(r => r.json()).then(setData);
    }, []);

    return <div>{data.map(t => <div key={t.id}>{t.title}</div>)}</div>;
});

// ✅ GOOD - Parent uses .bind() to invoke ServerRequest
<TaskList.bind requestType="GetTasksRequest" params={{}} />
```

### Pattern: No Hardcoded URLs

```jsx
// ❌ BAD - Hardcoded path
const TaskRow = viewModelComponent(({ viewModel }) => {
    return <a href={`/tasks/${viewModel.id}`}>{viewModel.title}</a>;
});

// ✅ GOOD - Navigation intent (requires router integration)
import { Link } from '/fosmvvm/react/navigation.js';

const TaskRow = viewModelComponent(({ viewModel }) => {
    return (
        <Link to={{ intent: 'viewTask', id: viewModel.id }}>
            {viewModel.title}
        </Link>
    );
});
```

## Version

These utilities are versioned with FOSUtilities SPM package. No version comments in files.

## License

Copyright (c) 2026 FOS Computer Services. All rights reserved.
Licensed under the Apache License, Version 2.0
