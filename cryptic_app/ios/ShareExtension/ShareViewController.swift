// Share Extension entry point.
//
// RSIShareViewController (from the receive_sharing_intent Swift package)
// copies the shared items into the App Group and redirects to the Runner app,
// where the Flutter plugin picks them up. The app then routes them to a peer.
import receive_sharing_intent

class ShareViewController: RSIShareViewController {
    // Default behaviour: redirect to the host app without showing a compose UI.
    override func shouldAutoRedirect() -> Bool {
        return true
    }
}
