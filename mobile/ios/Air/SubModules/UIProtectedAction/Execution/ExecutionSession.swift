import ProtectedAction
import UIKit
import UIComponents

@MainActor
final class ExecutionSessionRegistry {
    static let shared = ExecutionSessionRegistry()

    private var activeExecutionIds: [ObjectIdentifier: UUID] = [:]

    func acquire(in context: ExecutionContext) -> ExecutionSession? {
        let presentationSurface = context.authorizationPresenter.navigationController
            ?? context.authorizationPresenter
        let surfaceId = ObjectIdentifier(presentationSurface)
        guard activeExecutionIds[surfaceId] == nil else { return nil }
        let executionId = UUID()
        activeExecutionIds[surfaceId] = executionId
        return ExecutionSession(
            context: context,
            surfaceId: surfaceId,
            executionId: executionId,
            registry: self
        )
    }

    fileprivate func release(
        surfaceId: ObjectIdentifier,
        executionId: UUID
    ) {
        guard activeExecutionIds[surfaceId] == executionId else { return }
        activeExecutionIds[surfaceId] = nil
    }
}

@MainActor
final class ExecutionSession {
    private weak var authorizationPresenter: UIViewController?
    private weak var flowOrigin: UIViewController?
    private weak var navigationController: UINavigationController?
    private weak var presentationWindow: UIWindow?
    private weak var presentationOwner: UIViewController?
    private let isModalSurface: Bool
    private let surfaceId: ObjectIdentifier
    private let executionId: UUID
    private unowned let registry: ExecutionSessionRegistry
    private var didFinish = false

    fileprivate init(
        context: ExecutionContext,
        surfaceId: ObjectIdentifier,
        executionId: UUID,
        registry: ExecutionSessionRegistry
    ) {
        authorizationPresenter = context.authorizationPresenter
        flowOrigin = context.flowOrigin
        navigationController = context.authorizationPresenter.navigationController
        let presentationSurface = context.authorizationPresenter.navigationController
            ?? context.authorizationPresenter
        presentationWindow = presentationSurface.viewIfLoaded?.window
        presentationOwner = presentationSurface.presentingViewController
        isModalSurface = presentationSurface.presentingViewController != nil
        self.surfaceId = surfaceId
        self.executionId = executionId
        self.registry = registry
    }

    var configurationError: InvariantError? {
        guard let authorizationPresenter, let flowOrigin else {
            return .missingPresenter("execution context")
        }
        guard let navigationController else {
            guard authorizationPresenter === flowOrigin else {
                return .invalidConfiguration(
                    "authorization presenter and flow origin do not share a navigation controller"
                )
            }
            return nil
        }
        guard flowOrigin.navigationController === navigationController else {
            return .invalidConfiguration(
                "authorization presenter and flow origin use different navigation controllers"
            )
        }
        guard navigationController.viewControllers.contains(where: { $0 === flowOrigin }) else {
            return .invalidConfiguration("flow origin is not in the execution navigation stack")
        }
        return nil
    }

    var canPresentAuthorization: Bool {
        guard configurationError == nil, let authorizationPresenter else { return false }
        if let navigationController {
            return isSurfaceAttached(navigationController)
                && navigationController.viewIfLoaded?.window != nil
                && navigationController.topViewController === authorizationPresenter
                && navigationController.presentedViewController == nil
        }
        return isSurfaceAttached(authorizationPresenter)
            && authorizationPresenter.viewIfLoaded?.window != nil
            && authorizationPresenter.presentedViewController == nil
    }

    var isPresentationContextAlive: Bool {
        guard configurationError == nil,
              let authorizationPresenter,
              let flowOrigin
        else {
            return false
        }
        if let navigationController {
            return isSurfaceAttached(navigationController)
                && navigationController.viewControllers.contains(where: { $0 === authorizationPresenter })
                && navigationController.viewControllers.contains(where: { $0 === flowOrigin })
                && !navigationController.isBeingDismissed
        }
        return authorizationPresenter === flowOrigin
            && isSurfaceAttached(authorizationPresenter)
            && !authorizationPresenter.isBeingDismissed
    }

    func replaceCompletion(with replacement: Replacement) async -> Bool {
        guard isPresentationContextAlive,
              let navigationController,
              let targetStack = replacementStack(endingWith: replacement.viewController)
        else {
            return false
        }
        let coordinator = ContentReplaceAnimationCoordinator()
        return await coordinator.replaceNavigationStack(
            with: replacement.viewController,
            in: navigationController,
            targetViewControllers: targetStack,
            animateAlongside: replacement.animateAlongside,
            isValid: { [weak self] in
                self?.isPresentationContextAlive == true
            }
        )
    }

    func closeOriginatingFlow() {
        guard let flowOrigin else { return }
        guard let navigationController else {
            flowOrigin.dismiss(animated: true)
            return
        }
        if isModalSurface {
            navigationController.dismiss(animated: true)
            return
        }
        guard
            let index = navigationController.viewControllers.firstIndex(where: { $0 === flowOrigin }),
            index > 0
        else {
            flowOrigin.dismiss(animated: true)
            return
        }
        navigationController.setViewControllers(
            Array(navigationController.viewControllers.prefix(index)),
            animated: true
        )
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        registry.release(surfaceId: surfaceId, executionId: executionId)
    }

    private func replacementStack(endingWith viewController: UIViewController) -> [UIViewController]? {
        guard let navigationController, let flowOrigin else { return nil }
        if isModalSurface {
            return [viewController]
        }
        guard let index = navigationController.viewControllers.firstIndex(where: { $0 === flowOrigin }) else {
            return nil
        }
        return Array(navigationController.viewControllers.prefix(index)) + [viewController]
    }

    private func isSurfaceAttached(_ surface: UIViewController) -> Bool {
        if isModalSurface {
            return presentationOwner?.presentedViewController === surface
        }
        guard let rootViewController = presentationWindow?.rootViewController else { return false }
        var candidate: UIViewController? = surface
        while let current = candidate {
            if current === rootViewController {
                return true
            }
            candidate = current.parent
        }
        return false
    }
}
