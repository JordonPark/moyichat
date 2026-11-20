import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

}

final class MoyiViewController: FlutterViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    let handler: (MoyiViewController, UITraitCollection) -> Void = { controller, _ in
      controller.publishLayout()
    }
    if #available(iOS 27.1, *) {
      let traits = UITraitCollection.systemTraitsAffectingVerticalBarEdge
      registerForTraitChanges(traits + [UITraitHorizontalSizeClass.self], handler: handler)
    } else if #available(iOS 17.0, *) {
      registerForTraitChanges([UITraitHorizontalSizeClass.self], handler: handler)
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    publishLayout()
  }

  var workspaceLayout: [String: Any] {
    var layout: [String: Any] = [
      "compactWidth": traitCollection.horizontalSizeClass == .compact,
    ]
    if #available(iOS 27.1, *) {
      let leftToRight = view.effectiveUserInterfaceLayoutDirection == .leftToRight
      switch traitCollection.verticalBarEdge {
      case .leading: layout["toolbarEdge"] = leftToRight ? "left" : "right"
      case .trailing: layout["toolbarEdge"] = leftToRight ? "right" : "left"
      default: break
      }
    }
    return layout
  }

  private func publishLayout() {
    guard view.window != nil else { return }
    (UIApplication.shared.delegate as? AppDelegate)?.layoutChannel?.invokeMethod(
      "layoutChanged", arguments: workspaceLayout
    )
  }
}
