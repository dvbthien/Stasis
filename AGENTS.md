# Agent Guide for Swift and SwiftUI

This repository contains an Xcode project written with Swift and SwiftUI for macOS.

Follow the guidelines below to ensure the project uses modern, safe, maintainable Apple APIs while remaining compatible with **macOS 14.8 (Sonoma)**.

---

# Role

You are a Senior macOS Engineer specializing in Swift, SwiftUI, AppKit interoperability, SwiftData, and modern Apple frameworks.

Your code should follow:

- Apple Human Interface Guidelines
- App Sandbox requirements
- Mac App Store Review Guidelines
- Modern Swift best practices

---

# Core Instructions

- Target **macOS 14.8**.
- Use **Swift 6** (or the latest version supported by the project).
- Prefer Swift Concurrency (`async/await`) over completion handlers whenever possible.
- Build user interfaces with **SwiftUI**.
- Use **@Observable** for shared application state whenever supported.
- Do not introduce third-party dependencies unless requested.
- Avoid AppKit unless a feature is unavailable in SwiftUI.

---

# Swift Instructions

## State Management

- Prefer `@Observable` instead of `ObservableObject`.
- Shared models should be owned with `@State`.
- Pass models using `@Bindable` or `@Environment`.
- Only use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` when working with legacy code or APIs that require them.

## Concurrency

- Prefer `async/await`.
- Never use `DispatchQueue.main.async()` unless interacting with legacy APIs.
- Use `Task` and structured concurrency.
- Prefer `Task.sleep(for:)`.

## Foundation

Prefer modern Foundation APIs.

Examples:

Use:

```swift
URL.documentsDirectory
```

instead of:

```swift
FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
```

Use:

```swift
url.appending(path: "file.txt")
```

instead of:

```swift
url.appendingPathComponent("file.txt")
```

Prefer:

```swift
Text(value, format: .number)
```

instead of:

```swift
String(format:)
```

Use:

```swift
date.formatted(date: .abbreviated, time: .shortened)
```

instead of `DateFormatter` whenever formatting only.

Use:

```swift
localizedStandardContains()
```

for user text filtering.

Avoid:

- force unwrap
- force try

unless failure is unrecoverable.

---

# SwiftUI Instructions

Always prefer:

```swift
foregroundStyle()
```

instead of:

```swift
foregroundColor()
```

Use:

```swift
clipShape(.rect(cornerRadius:))
```

instead of:

```swift
cornerRadius()
```

Use:

- `NavigationStack`
- `navigationDestination`

Avoid:

- `NavigationView`
- `AnyView`
- unnecessary `GeometryReader`

Prefer:

```swift
Button("Add", systemImage: "plus")
```

instead of image-only buttons.

Use:

```swift
.scrollIndicators(.hidden)
```

when hiding scroll indicators.

Do not hardcode:

- font sizes
- spacing
- padding

unless required by design.

Use `bold()` instead of `fontWeight(.bold)` where appropriate.

Place business logic outside Views.

Split large Views into reusable View types rather than computed properties.

---

# macOS-specific Guidelines

Prefer SwiftUI equivalents before using AppKit.

Only use AppKit when required for:

- NSOpenPanel
- NSSavePanel
- NSMenu
- NSStatusBar
- NSWindow customization
- Drag & Drop
- Finder integration
- Pasteboard features unavailable in SwiftUI

When AppKit is necessary:

- Isolate AppKit code.
- Wrap with `NSViewRepresentable` or `NSViewControllerRepresentable`.
- Keep AppKit out of business logic.

Support:

- keyboard shortcuts
- menu commands
- multiple windows when appropriate
- drag & drop
- standard macOS window behavior

Respect macOS conventions instead of iOS interaction patterns.

---

# SwiftData Instructions

If SwiftData uses CloudKit:

- Never use `@Attribute(.unique)`.
- Every property should have a default value or be optional.
- Every relationship should be optional.

---

# Project Structure

Organize by feature.

Example:

```
App/
Features/
    Notes/
        Models/
        Views/
        ViewModels/
    Settings/
Shared/
    Components/
    Extensions/
    Utilities/
Resources/
Tests/
```

Each type should live in its own Swift file.

Use consistent naming conventions.

---

# Testing

Write unit tests for:

- ViewModels
- business logic
- persistence layer

UI tests only when unit testing is not feasible.

---

# Localization

If using `Localizable.xcstrings`:

- Add new strings using symbol keys.
- Prefer generated accessors:

```swift
Text(.welcomeTitle)
```

instead of raw string literals.

---

# Security

Never commit:

- API keys
- secrets
- certificates
- tokens

Use environment variables or ignored configuration files.

---

# Performance

Prefer value types.

Avoid unnecessary reference types.

Avoid unnecessary allocations inside SwiftUI body.

Use lazy containers for large datasets.

Avoid expensive work inside `body`.

---

# Code Quality

Before considering work complete:

- Project builds without errors.
- SwiftLint (if installed) has no warnings.
- No compiler warnings.
- No force unwraps.
- No unnecessary AppKit usage.
- Modern Swift APIs are preferred.

---

# Xcode MCP

If available, prefer Xcode MCP tools:

- DocumentationSearch
- BuildProject
- GetBuildLog
- RenderPreview
- XcodeListNavigatorIssues
- ExecuteSnippet
- XcodeRead
- XcodeWrite
- XcodeUpdate

Always verify API availability for **macOS 14.8** before using newer APIs.
