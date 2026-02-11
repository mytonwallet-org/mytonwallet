# Code Style Guide

This project follows the [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript) as its baseline. The rules below extend and override it where necessary.

---

## Naming

### General Rules

- **Functions and methods** start with an imperative verb: `showMessage()`, `updateUser()`, `runMethod()`. Exception: `callback`.
- **Acronyms** follow standard camelCase rules (no all-caps): `parseJson`, `jsonToYaml`, `isUiReady`.

### Boolean Variables and Props

Boolean variables and component props must always start with a modal verb:

```
is*    — isVisible, isUiReady
has*   — hasChanged
are*   — areMessagesLoaded (use `are` for plurals, never `is`)
should* — shouldRedirect
can*   — canComment
will*  — willChange
```

Exception: the argument `force`.

### Optional Boolean Arguments

Optional boolean function arguments and component props must default to `false`. This means if you need a prop that *hides* a user avatar, name it `noAvatar` rather than passing `hasAvatar={false}`.

### Allowed Abbreviations

| Short | Full       | Context                         |
|-------|------------|---------------------------------|
| `e`   | `event`    | Event handler argument          |
| `err` | `error`    | `catch` block argument          |
| `cb`  | `callback` | Callback-accepting functions    |

Single-letter element names are acceptable in one-line collection lambdas:

```ts
users.map(u => u.name);
```

Avoid all other abbreviations.

---

## Constants

Static constants must not appear inside function bodies. Hoist them to the top of the module with a descriptive `UPPER_SNAKE_CASE` name.

Bad:
```ts
function buildLayout() {
  const extraPadding = 16; // 1 rem
  width += 16 + 8;
}
```

Good:
```ts
const LAYOUT_EXTRA_PADDING = 16; // 1 rem
const LAYOUT_EXTRA_MARGIN = 8; // 0.5 rem

function buildLayout() {
  width += LAYOUT_EXTRA_PADDING + LAYOUT_EXTRA_MARGIN;
}
```

---

## Functions

### Declarations vs. Expressions

Prefer function declarations over function expressions, except when you need to bind `this` via an arrow function.

### Ordering

Functions are ordered top-down by call hierarchy: high-level functions at the top, low-level helpers at the bottom. ESLint rule:

```json
"@typescript-eslint/no-use-before-define": ["error", { "functions": false }]
```

### Cache Pure Function Results

If a pure function is called more than once within the same scope, store its result in a variable instead of calling it repeatedly.

### Avoid Unnecessary Function Calls

If a function cannot or should not run when an argument is absent, declare that argument as **required** and check for its presence at the **call site**, not inside the function.

Bad:
```ts
function someFunc(value?: string) {
  if (!value) return;
  // ...
}
someFunc(x);
```

Good:
```ts
function someFunc(value: string) {
  // ...
}
if (x) {
  someFunc(x);
}
```

---

## Control Flow

Prefer early returns (guard clauses) over large or deeply nested conditional blocks.

Bad:
```ts
function someFunc() {
  // ...
  if (condition) {
    // Large block of code
  }
}
```

Good:
```ts
function someFunc() {
  // ...
  if (!condition) {
    return;
  }
  // Large block of code
}
```

---

## Comments

- Comments start with a capital letter.
- Single-sentence comments have no trailing period.
- Multi-sentence comments end each sentence with a period.
- Code entities referenced in comments are wrapped in backticks `` ` ``.

---

## Dead Code

Do not keep unused code, "just in case" code, or speculative library-style utilities. If an object is not used outside its own module, it must not be exported.

---

## TypeScript

When a variable is guaranteed to exist at runtime but TypeScript cannot infer that, use the non-null assertion operator `!` instead of a conditional check.

```ts
// Correct
func(a!);

// Incorrect — do not guard when the value is guaranteed
if (a) func(a);
```

---

## Performance & React Optimization

### Global State Containers (`withGlobal`)

Minimize the number of global-connected containers. Never connect components that render inside loops — this creates N extra listeners for every global state change. Instead, pass the necessary props down from a parent container.

### No Loops in `mapStateToProps`

Loops inside `mapStateToProps` slow down the overall container evaluation on every global state change. Remove them.

### No New References in `mapStateToProps`

Never return array literals, object literals (including empty ones) from `mapStateToProps`. This breaks the shallow-equality check and causes unnecessary re-renders.

### `useLastCallback` Instead of `useCallback`

Use `useLastCallback` instead of `useCallback`. It avoids unwanted effect triggers and speeds up rendering by eliminating dependency comparison overhead.

### `useMemo` Usage

`useMemo` should be used **only** when:
- The computation contains loops or expensive operations, **or**
- It produces a complex object passed as a prop to a child `memo` component.

### `memo()` Wrapping

Wrap components in `memo()`, but **only** if none of their props are inherently non-memoizable (e.g. `children`).

---

## Backward Compatibility

- When adding a new required section to `GlobalState`, always add a corresponding entry in `migrateCache`.
- When changing types in global state or its nested objects, verify the migration path from the current `master` branch.

---

## CSS / Layout

- Avoid nested selectors and tag-based selectors. Every styled element must have its own class.
- Use `rem` instead of `px`. Conversion formula: `N px = N / 16 rem`.

