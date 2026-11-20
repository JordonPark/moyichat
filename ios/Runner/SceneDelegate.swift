import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

}

final class MoyiViewController: FlutterViewController {
  private static let toolbarExtent: CGFloat = 52
  private var lastPublishedLayout: NSDictionary?

  override func viewDidLoad() {
    super.viewDidLoad()
    let handler: (MoyiViewController, UITraitCollection) -> Void = { controller, _ in
      controller.publishLayout()
      controller.view.setNeedsLayout()
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

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    publishLayout()
  }

  var workspaceLayout: [String: Any] {
    var layout: [String: Any] = [
      "compactWidth": traitCollection.horizontalSizeClass == .compact,
    ]
    if #available(iOS 27.1, *) {
      let leftToRight = view.effectiveUserInterfaceLayoutDirection == .leftToRight
      let isLeft: Bool
      switch traitCollection.verticalBarEdge {
      case .leading: isLeft = leftToRight
      case .trailing: isLeft = !leftToRight
      default: return layout
      }
      layout["toolbarEdge"] = isLeft ? "left" : "right"
      let edge: UIRectEdge = isLeft ? .left : .right
      let guide = view.layoutGuide(for: .bar(onEdge: edge, extent: Self.toolbarExtent))
      let frame = guide.layoutFrame
      if !frame.isEmpty && frame.intersects(view.bounds) {
        layout["toolbarFrame"] = [
          Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height),
        ]
      }
    }
    return layout
  }

  private func publishLayout() {
    guard view.window != nil,
          let channel = (UIApplication.shared.delegate as? AppDelegate)?.layoutChannel
    else { return }
    let layout = workspaceLayout
    if lastPublishedLayout?.isEqual(to: layout) == true { return }
    lastPublishedLayout = NSDictionary(dictionary: layout)
    channel.invokeMethod("layoutChanged", arguments: layout)
  }
}
