# SpatialConsoleLogger

`SpatialConsoleLogger` is a Swift Package for visionOS apps. It captures tagged `print()` output and shows it in a separate floating SwiftUI window.

## Add To Another Xcode Project Locally

1. In Xcode, choose `File > Add Package Dependencies...`.
2. Select `Add Local...`.
3. Choose this folder:

   `<PATH TO REPO>/AVPLogger`

4. Add the `SpatialConsoleLogger` package product to your visionOS app target.

## Add As A Git Package

1. In Xcode, choose `File > Add Package Dependencies...`.
2. Enter the repository URL, for example:

   `git@github.com:sebrk/AVPLogger.git`

3. Choose the version rule, for example `Up to Next Major Version` from `1.0.0`.
4. Add the `SpatialConsoleLogger` package product to your visionOS app target.

## Use

Import the library:

```swift
import SpatialConsoleLogger
```

Keep your normal app scenes and add the logger to the root view that should start it:

```swift
var body: some Scene {
    WindowGroup(id: "MainWindow") {
        ContentView()
            .spatialConsoleLogger(tag: "TAG")
    }

    SpatialConsoleLoggerScene()
}
```

Existing `print()` output is captured when it includes the matching bracketed tag:

```swift
print("[TAG] App started")
```

You can also log directly:

```swift
startupLogWindow.log("App started")
```

If you prefer to keep a logger reference, create one and pass it to the same modifier:

```swift
private let startupLogWindow = SpatialConsoleLogger(tag: "TAG")

var body: some Scene {
    WindowGroup(id: "MainWindow") {
        ContentView()
            .spatialConsoleLogger(startupLogWindow)
    }

    SpatialConsoleLoggerScene()
}
```

There is also a `SpatialConsoleWindowGroup` convenience wrapper, but normal `WindowGroup` plus `.spatialConsoleLogger(tag:)` is the recommended integration for apps with multiple windows or immersive spaces.
