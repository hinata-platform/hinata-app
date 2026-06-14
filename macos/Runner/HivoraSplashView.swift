import Cocoa

/// Hivora native Splash-Animation für macOS (Core Animation / AppKit).
/// Gleiche Choreografie wie Android (AVD), iOS (UIKit) und Web (CSS).
final class HivoraSplashView: NSView {

    // MARK: - Public

    /// Über dem Flutter-View einblenden. Aufruf in MainFlutterWindow.awakeFromNib().
    static func present(over flutterView: NSView) {
        let splash = HivoraSplashView(frame: flutterView.bounds)
        splash.autoresizingMask = [.width, .height]
        flutterView.addSubview(splash)
        splash.start()
    }

    // MARK: - Layers

    private let markContainer = CALayer()
    private let hexLayer = CAShapeLayer()
    private let barLayer = CAShapeLayer()
    private let wordmark = NSTextField(labelWithString: "hivora")

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    private var markColor: NSColor {
        NSColor(red: 0.851, green: 0.627, blue: 0.196, alpha: 1) // #D9A032 honey-amber
    }
    private var inkColor: NSColor {
        isDark ? NSColor(red: 0.925, green: 0.922, blue: 0.953, alpha: 1) // #ECEBF3
               : NSColor(red: 0.137, green: 0.133, blue: 0.247, alpha: 1) // #23223F
    }
    private var bgColor: NSColor {
        isDark ? NSColor(red: 0.075, green: 0.067, blue: 0.098, alpha: 1) // #131119
               : NSColor(red: 0.957, green: 0.953, blue: 0.937, alpha: 1) // #F4F3EF
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor

        for shapeLayer in [hexLayer, barLayer] {
            shapeLayer.fillColor = nil
            shapeLayer.strokeColor = markColor.cgColor
            shapeLayer.lineCap = .round
            shapeLayer.lineJoin = .round
            shapeLayer.strokeEnd = 0
            markContainer.addSublayer(shapeLayer)
        }
        // macOS-Layer sind nicht geflippt — Pfade unten werden dafür gespiegelt angelegt
        layer?.addSublayer(markContainer)

        wordmark.textColor = inkColor
        wordmark.alphaValue = 0
        addSubview(wordmark)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Layout (responsiv: Logo = 30 % der kleineren Fenster-Kante)

    override func layout() {
        super.layout()
        let m = min(bounds.width, bounds.height)
        let markSize = m * 0.30
        let gap = m * 0.06
        let fontSize = m * 0.095

        wordmark.font = Self.soraFont(size: fontSize)
        wordmark.attributedStringValue = NSAttributedString(
            string: "hivora",
            attributes: [.kern: -0.03 * fontSize, .foregroundColor: inkColor]
        )
        wordmark.sizeToFit()

        let totalH = markSize + gap + wordmark.bounds.height
        // AppKit: y wächst nach oben — Wortmarke UNTER dem Logo platzieren
        let bottomY = (bounds.height - totalH) / 2

        wordmark.setFrameOrigin(NSPoint(
            x: (bounds.width - wordmark.bounds.width) / 2,
            y: bottomY
        ))
        markContainer.frame = CGRect(
            x: (bounds.width - markSize) / 2,
            y: bottomY + wordmark.bounds.height + gap,
            width: markSize,
            height: markSize
        )

        // Pfade aus dem 120-Einheiten-Designraum (y gespiegelt für AppKit)
        let s = markSize / 120.0
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * s, y: (120 - y) * s)
        }
        let hex = CGMutablePath()
        hex.move(to: p(60, 14))
        hex.addLine(to: p(99.8, 37))
        hex.addLine(to: p(99.8, 83))
        hex.addLine(to: p(60, 106))
        hex.addLine(to: p(20.2, 83))
        hex.addLine(to: p(20.2, 37))
        hex.closeSubpath()

        let bar = CGMutablePath()
        bar.move(to: p(20.2, 60))
        bar.addLine(to: p(99.8, 60))

        for shapeLayer in [hexLayer, barLayer] {
            shapeLayer.frame = markContainer.bounds
            shapeLayer.lineWidth = 11 * s
        }
        hexLayer.path = hex
        barLayer.path = bar
    }

    // MARK: - Animation

    private func start() {
        layoutSubtreeIfNeeded()
        let now = CACurrentMediaTime()

        let hexDraw = CABasicAnimation(keyPath: "strokeEnd")
        hexDraw.fromValue = 0
        hexDraw.toValue = 1
        hexDraw.duration = 0.62
        hexDraw.beginTime = now + 0.10
        hexDraw.timingFunction = CAMediaTimingFunction(controlPoints: 0.66, 0, 0.18, 1)
        hexDraw.fillMode = .both
        hexLayer.strokeEnd = 1
        hexLayer.add(hexDraw, forKey: "draw")

        let barDraw = CABasicAnimation(keyPath: "strokeEnd")
        barDraw.fromValue = 0
        barDraw.toValue = 1
        barDraw.duration = 0.38
        barDraw.beginTime = now + 0.50
        barDraw.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.18, 1)
        barDraw.fillMode = .both
        barLayer.strokeEnd = 1
        barLayer.add(barDraw, forKey: "draw")

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.94
        pop.toValue = 1.0
        pop.damping = 12
        pop.stiffness = 220
        pop.beginTime = now + 0.62
        pop.duration = pop.settlingDuration
        pop.fillMode = .both
        markContainer.add(pop, forKey: "pop")

        let rise = CABasicAnimation(keyPath: "opacity")
        rise.fromValue = 0
        rise.toValue = 1
        rise.duration = 0.55
        rise.beginTime = now + 0.88
        rise.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        rise.fillMode = .both
        wordmark.layer?.add(rise, forKey: "rise")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.88) { [weak self] in
            self?.wordmark.alphaValue = 1
        }

        // Ausblenden, sobald die Choreografie durch ist
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                self.animator().alphaValue = 0
            }, completionHandler: {
                self.removeFromSuperview()
            })
        }
    }

    // MARK: - Sora Variable Font (wght 600), Fallback: System Semibold

    private static var fontRegistered = false

    private static func soraFont(size: CGFloat) -> NSFont {
        if !fontRegistered,
           let url = Bundle.main.url(forResource: "Sora-Variable", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            fontRegistered = true
        }
        guard let base = NSFont(name: "Sora-Regular", size: size) else {
            return NSFont.systemFont(ofSize: size, weight: .semibold)
        }
        let variation = [2003265652: 600] // 'wght' Achsen-Tag
        let descriptor = base.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}
