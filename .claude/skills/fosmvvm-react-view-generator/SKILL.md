---
name: fosmvvm-react-view-generator
description: Generate React ViewModelViews following FOSMVVM patterns. Use when creating UI that renders ViewModels in React applications.
---

# FOSMVVM React View Generator

Generate React components that render FOSMVVM ViewModels.

## Conceptual Foundation

> For full architecture context, see [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md)

In FOSMVVM, **React components are thin rendering layers** that display ViewModels:

```
┌─────────────────────────────────────────────────────────────┐
│                    ViewModelView Pattern                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ViewModel (Data)          React Component                  │
│  ┌──────────────────┐     ┌──────────────────┐             │
│  │ title: String    │────►│ <h1>{vm.title}   │             │
│  │ items: [Item]    │────►│ {vm.items.map()} │             │
│  │ isEnabled: Bool  │────►│ disabled={!...}  │             │
│  └──────────────────┘     └──────────────────┘             │
│                                                              │
│  ServerRequest (Actions)                                     │
│  ┌──────────────────┐     ┌──────────────────┐             │
│  │ processRequest() │◄────│ <Component.bind  │             │
│  │                  │     │   requestType={} │             │
│  └──────────────────┘     └──────────────────┘             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Key principle:** Components don't transform or compute data. They render what the ViewModel provides.

---

## View-ViewModel Alignment

**The component filename should match the ViewModel it renders.**

```
src/
  viewmodels/
    {Feature}ViewModel.js           ←──┐
    {Entity}CardViewModel.js        ←──┼── Same names
                                        │
  components/                           │
    {Feature}/                          │
      {Feature}View.jsx             ────┤  (renders {Feature}ViewModel)
      {Entity}CardView.jsx          ────┘  (renders {Entity}CardViewModel)
```

This alignment provides:
- **Discoverability** - Find the component for any ViewModel instantly
- **Consistency** - Same naming discipline as SwiftUI and Leaf
- **Maintainability** - Changes to ViewModel are reflected in component location

---

## TDD Workflow

This skill generates **tests FIRST, implementation SECOND** in a single invocation:

```
1. Read specification (file or conversational)
2. Generate .test.js file → Tests FAIL (no implementation yet)
3. Generate .jsx file → Tests PASS
4. Verify completeness (both files exist)
5. User runs `npm test` → All tests pass ✓
```

**No prompting between test and implementation.** Both files created automatically.

---

## Core Components

### 1. viewModelComponent() Wrapper

Every component is wrapped with `viewModelComponent()`:

```jsx
import { viewModelComponent } from '/fosmvvm/react/viewModelComponent.js';

const MyView = viewModelComponent(({ viewModel }) => {
  return <div>{viewModel.title}</div>;
});

export default MyView;
```

**Required:**
- `import { viewModelComponent }` from `/fosmvvm/react/viewModelComponent.js`
- Component function receives `{ viewModel }` prop
- Wrap with `viewModelComponent()` before export

### 2. The .bind() Pattern

Parent components use `.bind()` to invoke ServerRequests:

```jsx
// Parent component
function Dashboard() {
  return (
    <div>
      <TaskList.bind({
        requestType: 'GetTasksRequest',
        params: { status: 'active' }
      }) />
    </div>
  );
}
```

**The .bind() pattern:**
- Child components receive data via ServerRequest
- Parent specifies `requestType` and `params`
- WASM bridge handles request → ViewModel → component rendering
- No fetch() calls, no hardcoded URLs

### 3. Error ViewModel Handling

Error ViewModels are rendered like any other ViewModel:

```jsx
const TaskCard = viewModelComponent(({ viewModel }) => {
  // Handle error ViewModels
  if (viewModel.errorType === 'NotFoundError') {
    return (
      <div className="error">
        <p>{viewModel.message}</p>
        <p>{viewModel.suggestedAction}</p>
      </div>
    );
  }

  if (viewModel.errorType === 'ValidationError') {
    return (
      <div className="validation-error">
        <h3>{viewModel.title}</h3>
        <ul>
          {viewModel.errors.map(err => (
            <li key={err.field}>{err.message}</li>
          ))}
        </ul>
      </div>
    );
  }

  // Render success ViewModel
  return (
    <div className="task-card">
      <h3>{viewModel.title}</h3>
      <p>{viewModel.description}</p>
    </div>
  );
});
```

**Key principles:**
- No generic error handling
- Each error type has its own ViewModel
- Component conditionally renders based on `errorType` property
- Error rendering is just data rendering

### 4. Navigation Intents (Not URLs)

Use navigation intents, not hardcoded paths:

```jsx
import { Link } from '/fosmvvm/react/navigation.js';

// ❌ NEVER
<a href="/tasks/123">View Task</a>

// ✅ ALWAYS
<Link to={{ intent: 'viewTask', id: viewModel.id }}>
  {viewModel.linkText}
</Link>
```

**Navigation patterns:**
- Import `Link` from `/fosmvvm/react/navigation.js`
- Use `intent` property, not hardcoded paths
- Router maps intents to routes
- Platform-independent navigation

---

## Component Categories

### Display-Only Components

Components that just render data (no user interactions):

```jsx
const InfoCard = viewModelComponent(({ viewModel }) => {
  return (
    <div className="info-card">
      <h2>{viewModel.title}</h2>
      <p>{viewModel.description}</p>

      {viewModel.isActive && (
        <span className="badge">{viewModel.activeLabel}</span>
      )}
    </div>
  );
});

export default InfoCard;
```

**Characteristics:**
- Just renders ViewModel properties
- No event handlers (onClick, onSubmit, etc.)
- May have conditional rendering based on ViewModel state
- No .bind() calls to child components

### Interactive Components

Components with user actions that trigger ServerRequests:

```jsx
const ActionCard = viewModelComponent(({ viewModel }) => {
  return (
    <div className="action-card">
      <h2>{viewModel.title}</h2>
      <p>{viewModel.description}</p>

      <div className="actions">
        <button
          onClick={() => viewModel.operations.performAction()}
          disabled={!viewModel.canPerformAction}
        >
          {viewModel.actionLabel}
        </button>

        <button onClick={() => viewModel.operations.cancel()}>
          {viewModel.cancelLabel}
        </button>
      </div>
    </div>
  );
});

export default ActionCard;
```

### List Components

Components that render collections:

```jsx
const TaskList = viewModelComponent(({ viewModel }) => {
  if (viewModel.isEmpty) {
    return <div className="empty">{viewModel.emptyMessage}</div>;
  }

  return (
    <div className="task-list">
      <h2>{viewModel.title}</h2>
      <p>{viewModel.totalCount}</p>

      {viewModel.tasks.map(task => (
        <TaskCard.bind({
          requestType: 'GetTaskRequest',
          params: { id: task.id }
        }) />
      ))}
    </div>
  );
});

export default TaskList;
```

### Form Components

Components with validated input fields:

```jsx
const SignInForm = viewModelComponent(({ viewModel }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [errors, setErrors] = useState({});

  const handleSubmit = async (e) => {
    e.preventDefault();

    const result = await viewModel.operations.submit({
      email,
      password
    });

    if (result.validationErrors) {
      setErrors(result.validationErrors);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <div>
        <label>{viewModel.emailLabel}</label>
        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder={viewModel.emailPlaceholder}
        />
        {errors.email && <span className="error">{errors.email}</span>}
      </div>

      <div>
        <label>{viewModel.passwordLabel}</label>
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder={viewModel.passwordPlaceholder}
        />
        {errors.password && <span className="error">{errors.password}</span>}
      </div>

      <button type="submit" disabled={viewModel.submitDisabled}>
        {viewModel.submitLabel}
      </button>
    </form>
  );
});

export default SignInForm;
```

---

## When to Use This Skill

- Creating a new React component for a FOSMVVM app
- Building UI to render a ViewModel
- Migrating Leaf templates to React
- Following an implementation plan that requires new views
- Creating forms with validation
- Building list views that compose child components

---

## What This Skill Generates

**Two files per invocation:**

| File | Location | Purpose |
|------|----------|---------|
| `{ViewName}View.test.js` | `src/components/{Feature}/` | Jest + React Testing Library tests |
| `{ViewName}View.jsx` | `src/components/{Feature}/` | React component |

**Test file generated FIRST (tests fail initially)**
**Implementation file generated SECOND (tests pass)**

**Note:** The corresponding ViewModel and ServerRequest should already exist (use other FOSMVVM generator skills).

---

## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{ViewName}` | View name (without "View" suffix) | `TaskList`, `SignIn` |
| `{Feature}` | Feature/module grouping | `Tasks`, `Auth` |

---

## Generation Process

### Step 1: Determine Component Type

Ask:
1. **What ViewModel does this render?** → Determines the data source
2. **What ServerRequest provides the ViewModel?** → Determines the .bind() pattern
3. **Is this display-only or interactive?** → Determines if operations needed
4. **Is this a form with validation?** → Determines if form state needed
5. **Does this compose child components?** → Determines if .bind() calls needed

### Step 2: Identify Required Tests

Based on component type:
- **Display-only**: Test rendering with success ViewModel, error ViewModels
- **Interactive**: Add tests for button clicks, operation calls
- **Form**: Add tests for input changes, validation errors, submission
- **List**: Add tests for empty state, multiple items, child binding

### Step 3: Generate Test File (FIRST)

Create `.test.js` with:
1. Import React Testing Library
2. Import the component (won't exist yet)
3. Test rendering with success ViewModel
4. Test rendering with error ViewModels
5. Test user interactions (if interactive)
6. Test form submission (if form)
7. Test child .bind() calls (if container)

### Step 4: Generate Component File (SECOND)

Create `.jsx` with:
1. Import `viewModelComponent` from `/fosmvvm/react/viewModelComponent.js`
2. Define component function receiving `{ viewModel }`
3. Handle error ViewModels with conditional rendering
4. Render success ViewModel
5. Add event handlers for interactions (if interactive)
6. Add form state management (if form)
7. Add child .bind() calls (if container)
8. Wrap with `viewModelComponent()` and export

### Step 5: Verify Completeness

Check:
- [ ] `.test.js` file exists
- [ ] `.jsx` file exists
- [ ] Component references `/fosmvvm/react/viewModelComponent.js`
- [ ] Component uses `viewModelComponent()` wrapper
- [ ] Tests cover success and error ViewModels
- [ ] Tests cover user interactions (if applicable)

---

## Key Patterns

### Pattern: No Business Logic in Components

```jsx
// ❌ BAD - Component is transforming data
const TaskCard = viewModelComponent(({ viewModel }) => {
  const daysLeft = Math.ceil((viewModel.dueDate - Date.now()) / 86400000);
  return <span>{daysLeft} days remaining</span>;
});

// ✅ GOOD - ViewModel provides shaped result
const TaskCard = viewModelComponent(({ viewModel }) => {
  return <span>{viewModel.daysRemainingText}</span>;
});
```

### Pattern: No fetch() Calls

```jsx
// ❌ BAD - Component making HTTP requests
const TaskCard = viewModelComponent(({ viewModel }) => {
  const [data, setData] = useState(null);

  useEffect(() => {
    fetch(`/api/tasks/${viewModel.id}`)
      .then(r => r.json())
      .then(setData);
  }, [viewModel.id]);

  return <div>{data?.title}</div>;
});

// ✅ GOOD - Parent uses .bind() to invoke ServerRequest
<TaskCard.bind({
  requestType: 'GetTaskRequest',
  params: { id: taskId }
}) />
```

### Pattern: Error ViewModels Are Data

```jsx
// ❌ BAD - Generic error handling
const TaskCard = viewModelComponent(({ viewModel }) => {
  if (viewModel.error) {
    return <div>Error: {viewModel.error.message}</div>;
  }
  return <div>{viewModel.title}</div>;
});

// ✅ GOOD - Specific error ViewModels
const TaskCard = viewModelComponent(({ viewModel }) => {
  if (viewModel.errorType === 'NotFoundError') {
    return (
      <div className="not-found">
        <h3>{viewModel.errorTitle}</h3>
        <p>{viewModel.errorMessage}</p>
        <p>{viewModel.suggestedAction}</p>
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

  return <div>{viewModel.title}</div>;
});
```

### Pattern: Navigation Intents

```jsx
// ❌ BAD - Hardcoded URLs
const TaskRow = viewModelComponent(({ viewModel }) => {
  return (
    <div>
      <a href={`/tasks/${viewModel.id}`}>{viewModel.title}</a>
    </div>
  );
});

// ✅ GOOD - Navigation intents
import { Link } from '/fosmvvm/react/navigation.js';

const TaskRow = viewModelComponent(({ viewModel }) => {
  return (
    <div>
      <Link to={{ intent: 'viewTask', id: viewModel.id }}>
        {viewModel.title}
      </Link>
    </div>
  );
});
```

---

## File Organization

```
src/components/
├── {Feature}/
│   ├── {Feature}View.jsx             # Full page → {Feature}ViewModel
│   ├── {Feature}View.test.js         # Tests for {Feature}View
│   ├── {Entity}CardView.jsx          # Child component → {Entity}CardViewModel
│   ├── {Entity}CardView.test.js      # Tests for {Entity}CardView
│   └── {Entity}RowView.jsx           # Child component → {Entity}RowViewModel
├── Shared/
│   ├── HeaderView.jsx                # Shared components
│   └── FooterView.jsx
```

---

## Common Mistakes

### Computing Data in Components

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

### Making HTTP Requests Directly

```jsx
// ❌ BAD - fetch() call in component
const TaskList = viewModelComponent(({ viewModel }) => {
  const [tasks, setTasks] = useState([]);

  useEffect(() => {
    fetch('/api/tasks').then(r => r.json()).then(setTasks);
  }, []);

  return <div>{tasks.map(t => <div key={t.id}>{t.title}</div>)}</div>;
});

// ✅ GOOD - Parent uses .bind() with ServerRequest
<TaskList.bind({
  requestType: 'GetTasksRequest',
  params: {}
}) />
```

### Hardcoding Text

```jsx
// ❌ BAD - Not localizable
const TaskCard = viewModelComponent(({ viewModel }) => {
  return (
    <button onClick={viewModel.operations.submit}>
      Submit
    </button>
  );
});

// ✅ GOOD - ViewModel provides localized text
const TaskCard = viewModelComponent(({ viewModel }) => {
  return (
    <button onClick={viewModel.operations.submit}>
      {viewModel.submitLabel}
    </button>
  );
});
```

### Using Hardcoded URLs

```jsx
// ❌ BAD - Hardcoded path
const TaskRow = viewModelComponent(({ viewModel }) => {
  return <a href={`/tasks/${viewModel.id}`}>{viewModel.title}</a>;
});

// ✅ GOOD - Navigation intent
import { Link } from '/fosmvvm/react/navigation.js';

const TaskRow = viewModelComponent(({ viewModel }) => {
  return (
    <Link to={{ intent: 'viewTask', id: viewModel.id }}>
      {viewModel.title}
    </Link>
  );
});
```

### Not Wrapping with viewModelComponent()

```jsx
// ❌ BAD - Missing viewModelComponent() wrapper
const TaskCard = ({ viewModel }) => {
  return <div>{viewModel.title}</div>;
};
export default TaskCard;

// ✅ GOOD - Wrapped with viewModelComponent()
import { viewModelComponent } from '/fosmvvm/react/viewModelComponent.js';

const TaskCard = viewModelComponent(({ viewModel }) => {
  return <div>{viewModel.title}</div>;
});
export default TaskCard;
```

### Mismatched Filenames

```
// ❌ BAD - Filename doesn't match ViewModel
ViewModel: TaskListViewModel
Component: Tasks.jsx

// ✅ GOOD - Aligned names
ViewModel: TaskListViewModel
Component: TaskListView.jsx
```

---

## File Templates

See [reference.md](reference.md) for complete file templates.

---

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| Component file | `{Name}View.jsx` | `TaskListView.jsx`, `SignInView.jsx` |
| Test file | `{Name}View.test.js` | `TaskListView.test.js` |
| Component function | `{Name}View` | `TaskListView`, `SignInView` |
| ViewModel prop | `viewModel` | Always `viewModel` |

---

## Testing Patterns

### Test: Rendering with Success ViewModel

```javascript
it('renders task card with ViewModel', () => {
  const viewModel = {
    title: 'Test Task',
    description: 'Test Description',
    dueDate: 'Jan 30, 2026'
  };

  render(<TaskCard viewModel={viewModel} />);

  expect(screen.getByText('Test Task')).toBeInTheDocument();
  expect(screen.getByText('Test Description')).toBeInTheDocument();
});
```

### Test: Rendering with Error ViewModel

```javascript
it('renders NotFoundViewModel', () => {
  const viewModel = {
    errorType: 'NotFoundError',
    errorTitle: 'Task Not Found',
    errorMessage: 'The task you requested does not exist',
    suggestedAction: 'Try searching for a different task'
  };

  render(<TaskCard viewModel={viewModel} />);

  expect(screen.getByText('Task Not Found')).toBeInTheDocument();
  expect(screen.getByText(/does not exist/)).toBeInTheDocument();
});
```

### Test: User Interaction

```javascript
it('calls operation when button clicked', () => {
  const mockOperation = jest.fn();
  const viewModel = {
    title: 'Test Task',
    submitLabel: 'Complete Task',
    operations: {
      complete: mockOperation
    }
  };

  render(<TaskCard viewModel={viewModel} />);

  fireEvent.click(screen.getByText('Complete Task'));

  expect(mockOperation).toHaveBeenCalled();
});
```

---

## Collaboration Protocol

1. Confirm the ViewModel exists and understand its structure
2. Identify the ServerRequest that provides the ViewModel
3. Determine if the component needs operations (interactive vs display-only)
4. Identify if this is a form (needs validation)
5. Identify if this composes child components (needs .bind())
6. Generate test file (tests fail initially)
7. Generate component file (tests pass)
8. Verify completeness (both files exist)

---

## See Also

- [Architecture Patterns](../shared/architecture-patterns.md) - Mental models and patterns
- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Full FOSMVVM architecture
- [fosmvvm-swiftui-view-generator](../fosmvvm-swiftui-view-generator/SKILL.md) - SwiftUI equivalent
- [fosmvvm-leaf-view-generator](../fosmvvm-leaf-view-generator/SKILL.md) - Leaf equivalent
- [reference.md](reference.md) - Complete file templates

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-23 | Initial skill for React view generation based on Kairos requirements |
