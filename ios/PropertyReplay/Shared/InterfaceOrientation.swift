import SwiftUI
import UIKit

/// Reports the interface orientation of the window a view lives in: on appearance, after every layout, and when the
/// device turns. SwiftUI has no environment value for it, and the compass needs it (CLHeading measures from the top
/// edge of the device). Put it in a `.background`; it draws nothing and takes no touches.
struct InterfaceOrientationReader: UIViewRepresentable {
    let onChange: (UIInterfaceOrientation) -> Void

    func makeUIView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ReportingView, context: Context) { uiView.onChange = onChange }

    final class ReportingView: UIView {
        var onChange: ((UIInterfaceOrientation) -> Void)?
        private var last: UIInterfaceOrientation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Selector observers are removed by the system when the view goes away.
            NotificationCenter.default.addObserver(self, selector: #selector(turned), name: UIDevice.orientationDidChangeNotification, object: nil)
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        @objc private func turned() { report() }

        private func report() {
            guard let orientation = window?.windowScene?.interfaceOrientation, orientation != last else { return }
            last = orientation
            onChange?(orientation)
        }
    }
}
