import SwiftUI

/// The Command Line Tools ship without the SwiftUI macro plugin, so `@State` (now a macro in the
/// macOS 26+ SDK) fails to build without full Xcode. This alias resolves to the plain property
/// wrapper instead, so the project builds with either toolchain.
typealias ViewState<Value> = SwiftUI.State<Value>
