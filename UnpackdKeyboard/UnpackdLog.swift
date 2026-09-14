//
//  UnpackdLog.swift
//  UnpackdKeyboard
//
//  Debug logging that is actually readable from an app extension.
//

import os

/// Where this target's debug output goes.
///
/// WHY NOT `print`
/// `print` writes to stdout, and an app extension's stdout is not connected to
/// anything a developer can read: the extension runs as an XPC service hosted
/// by the foreground app, not under a terminal or Xcode's console, so the text
/// is discarded. A device log capture taken while the keyboard was demonstrably
/// alive — the view controller instantiated, Foundation Models prewarmed —
/// contained hundreds of lines from Apple's own frameworks and not one line
/// from this target, because theirs go through `os_log` and ours did not. The
/// absence of output was mistaken for the extension failing to launch.
///
/// `Logger` writes to the unified log, which `idevicesyslog`, Console.app and
/// `log collect` all read, so these lines survive the trip out of the
/// extension sandbox.
///
/// PRIVACY
/// The unified log redacts interpolated values by default, which is why so
/// much of Apple's output above reads `<private>`. The draft is the user's
/// unsent message at their worst moment, so it stays redacted in any build
/// that is not a local debug one — see `Unpackd.draft(_:)`.
enum Unpackd {

    static let log = Logger(subsystem: "com.hoamedigital.unpackd.keyboard", category: "reflect")

    /// A draft rendered for the log.
    ///
    /// Truncated and marked `.private`, so it is visible when you are
    /// debugging on your own device and redacted to `<private>` in any capture
    /// taken from a build someone else is running. This text is the whole
    /// reason the product promises to keep everything on-device; it must not
    /// become readable in a sysdiagnose a user sends to Apple.
    static func draft(_ text: String) -> String {
        String(text.prefix(60))
    }
}
