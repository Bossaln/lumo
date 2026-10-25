import AppKit
import NotchaiCore
import SwiftUI

/// Randloses, durchsichtiges Panel oben auf der Notch. Klicks gehen standardmäßig hindurch.
final class NotchPanel: NSPanel {
    /// Rand rund um die größte Darstellung, damit das Leuchten nicht abgeschnitten wird.
    static let glowMargin: CGFloat = 40

    init(rootView: NotchRootView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        // Die App ist nie aktiv; ohne das würde das Panel sofort wieder verschwinden.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        let host = FirstClickHostingView(rootView: rootView)
        host.sizingOptions = []
        contentView = host
    }

    /// AppKit soll das Panel nicht unter die Menüleiste schieben.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Entscheidet, ob das Panel gerade Tastatureingaben annehmen darf (nur fürs Antwortfeld).
    var keyPolicy: (() -> Bool)?

    override var canBecomeKey: Bool { keyPolicy?() ?? false }

    /// Setzt das Panel oben bündig und mittig auf die Notch, groß genug für jede Darstellung.
    func position(around notch: CGRect, islandSideWidth: CGFloat) {
        let contentWidth = max(NotchGeometry.bannerMaxWidth, NotchGeometry.panelWidth,
                               NotchGeometry.verticalWidth, NotchGeometry.islandWidth(notch: notch, sideWidth: islandSideWidth),
                               notch.width + 2 * NotchGeometry.trackSideWidth, NotchGeometry.trackBannerWidth)
        let contentHeight = max(NotchGeometry.panelMaxHeight,
                                notch.height + NotchGeometry.bannerExtraHeight,
                                notch.height + NotchGeometry.verticalExtraHeight,
                                notch.height + NotchGeometry.trackBannerExtraHeight)
        let width = contentWidth + 2 * Self.glowMargin
        let height = contentHeight + Self.glowMargin
        // Ohne sofortiges Neuzeichnen: SwiftUI zeichnet im nächsten Durchlauf ohnehin.
        setFrame(NSRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height),
                 display: false)
    }
}

/// Nimmt schon den ersten Klick an, obwohl das Panel nie aktiv wird.
private final class FirstClickHostingView: NSHostingView<NotchRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// SwiftUI rechnet hier die Notch neu; die Seite „Entwickler“ › Reaktion misst, wie lange das dauert.
    override func layout() {
        MainThreadWork.measure("NotchView.layout") { super.layout() }
    }
}
