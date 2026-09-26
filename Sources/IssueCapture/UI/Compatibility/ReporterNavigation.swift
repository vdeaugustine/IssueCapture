import SwiftUI

struct ReporterNavigation<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 16, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content).navigationViewStyle(.stack)
        }
    }
}

extension View {
    @ViewBuilder func reporterDestination<Destination: View>(
        isPresented: Binding<Bool>, @ViewBuilder destination: () -> Destination
    ) -> some View {
        if #available(iOS 16, *) {
            navigationDestination(isPresented: isPresented, destination: destination)
        } else {
            background(NavigationLink(isActive: isPresented, destination: destination,
                                      label: { EmptyView() }).hidden())
        }
    }

    @ViewBuilder func reporterSectionSpacing() -> some View {
        if #available(iOS 17, *) { listSectionSpacing(16) } else { self }
    }

    @ViewBuilder func reporterKeyboardDismissal() -> some View {
        if #available(iOS 16, *) { scrollDismissesKeyboard(.interactively) } else { self }
    }
}

extension ToolbarItemPlacement {
    static var reporterSecondaryAction: ToolbarItemPlacement {
        if #available(iOS 16, *) { return .secondaryAction }
        return .navigationBarTrailing
    }
}

extension View {
    @ViewBuilder func reporterScrollClip() -> some View {
        if #available(iOS 17, *) { scrollClipDisabled() } else { self }
    }
}
