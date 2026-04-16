import UIKit

final class AppOrientationCoordinator: ObservableObject {
    static let shared = AppOrientationCoordinator()

    @Published var allowedMask: UIInterfaceOrientationMask = .portrait

    private init() {}

    func requestOrientation(_ target: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.activeWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationCoordinator.shared.allowedMask
    }
}

extension UIApplication {
    var activeWindowScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}
