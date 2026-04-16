import SwiftUI

struct ScrollViewOffsetReader: UIViewRepresentable {
    let onOffsetChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = _OffsetIntrospectionView()
        view.onOffsetChange = onOffsetChange
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private class _OffsetIntrospectionView: UIView {
        var onOffsetChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
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
