import Foundation
import Observation

/// The two editable texts behind a pasted-text comparison. A reference type so the text survives
/// the detail view being torn down when the user switches to another sidebar item and back.
@Observable
final class PastedTextDocument {
    var a: String
    var b: String

    init(a: String = "", b: String = "") {
        self.a = a
        self.b = b
    }
}

extension PastedTextDocument: Hashable {
    static func == (lhs: PastedTextDocument, rhs: PastedTextDocument) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
