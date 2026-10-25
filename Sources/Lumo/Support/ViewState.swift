import SwiftUI

/// SwiftUIs `@State` ist im macOS-27-SDK zusätzlich ein Makro (`SwiftUIMacros.StateMacro`), dessen
/// Plugin nur mit Xcode ausgeliefert wird. Mit den Command Line Tools schlägt `@State` deshalb fehl.
/// Über diesen Alias wird direkt der Property Wrapper `State<Value>` benutzt, ohne Makro.
typealias ViewState<Value> = SwiftUI.State<Value>
