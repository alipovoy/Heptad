import SwiftUI

/// The strip above the editor that says nothing is being kept.
///
/// Not a `ContentUnavailableView` in the editor's place. On `.notSaving` the notes on screen are
/// the user's real ones, read from the file, and taking the editor away would take with it the
/// only way to get them out. On `.ephemeral` there is nothing to rescue, but a menubar scratchpad
/// that refuses to hold a note for the session is worse than one that warns it will not keep it.
///
/// Not dismissible, for the reason it exists: neither condition is recoverable without a relaunch,
/// so a banner that can be waved away is a banner the user spends the rest of the session without.
struct StoreHealthBanner: View {
    let health: StoreHealth

    /// How much of the warning colour the strip is washed with. Deliberately a wash rather than a
    /// fill: this sits directly above the editor, which is itself tinted with the note's colour,
    /// and a solid bar reads as chrome the app does not otherwise have.
    private static let fillOpacity = 0.18

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.primary)
                // Wraps rather than truncates: the macOS panel is 320pt at its narrowest, which
                // is not a line's worth of either sentence below.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppConstants.Layout.edgeInset)
                .padding(.vertical, AppConstants.Layout.rowInset)
                .background(Color.red.opacity(Self.fillOpacity))
                // One announcement, so VoiceOver reads the sentence instead of the warning
                // triangle and then the sentence.
                .accessibilityElement(children: .combine)
        }
    }

    /// What the strip says, or nothing at all on a healthy store.
    ///
    /// Both sentences lead with the consequence rather than the cause: "not saving" is the part
    /// that changes what the user does next, and on a 320pt panel it is the part guaranteed to be
    /// on the first line.
    private var message: String? {
        switch health {
        case .healthy:
            return nil
        case .notSaving:
            return "Not saving — the note store will not take changes. Copy anything you need out."
        case .ephemeral:
            return "Not saving — your notes could not be opened. Anything typed here is lost when "
                + "Heptad quits."
        }
    }
}

#Preview("Not saving") {
    StoreHealthBanner(health: .notSaving)
        .frame(width: AppConstants.Window.minimumContentSize.width)
}

#Preview("In memory") {
    StoreHealthBanner(health: .ephemeral)
        .frame(width: AppConstants.Window.minimumContentSize.width)
}
