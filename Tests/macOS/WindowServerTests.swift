import Testing

/// Everything that needs the window server, under one serialized roof.
///
/// `.serialized` on a top-level suite orders the tests *within* it and does nothing about the
/// suites running beside it — top-level suites run in parallel regardless. The four suites nested
/// here each put real `NSWindow`s on screen and read `isKeyWindow`, `isVisible` and `frame.origin`
/// back; the window server is process-wide, so in parallel they read each other's answers.
///
/// Nesting rather than one merged file: the trait applies to everything inside the suite, and a
/// nested suite is inside it even when the extension that declares it lives in another file.
@MainActor
@Suite(.serialized, .tags(.windowServer))
struct WindowServerTests {}
