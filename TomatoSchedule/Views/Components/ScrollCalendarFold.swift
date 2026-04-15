import SwiftUI

// MARK: - iOS 17 scroll offset observer (UIKit KVO inside List row → finds UIScrollView)

struct ScrollOffsetObserver: UIViewRepresentable {
    let onOffsetChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = _IntrospectionView()
        view.onOffsetChange = onOffsetChange
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private class _IntrospectionView: UIView {
        var onOffsetChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            trySetupObservation()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            trySetupObservation()
        }

        private func trySetupObservation() {
            guard observation == nil, window != nil else { return }
            var current: UIView? = superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    observation = scrollView.observe(\.contentOffset, options: .new) { [weak self] sv, _ in
                        DispatchQueue.main.async {
                            self?.onOffsetChange?(sv.contentOffset.y)
                        }
                    }
                    return
                }
                current = view.superview
            }
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            if newWindow == nil { observation?.invalidate(); observation = nil }
        }
    }
}

// MARK: - Scroll-driven calendar fold modifier (iOS 18 only)

struct ScrollCalendarFoldModifier: ViewModifier {
    @Binding var isExpanded: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { _, newValue in
                    if newValue > 60 && isExpanded {
                        withAnimation(.easeInOut(duration: 0.3)) { isExpanded = false }
                    }
                    if newValue < -10 && !isExpanded {
                        withAnimation(.easeInOut(duration: 0.3)) { isExpanded = true }
                    }
                }
        } else {
            // iOS 17: observer placed inside List row (see lessonList)
            content
        }
    }
}
