import Foundation

/// A recorded action captured during recorder session
struct RecordedAction: Identifiable {
    let id: UUID = UUID()
    let type: String  // "click", "type", "scroll", etc.
    let name: String
    let details: [String: String]  // key-value pairs for action details
    let assertions: [RecordedAssertion]

    init(type: String, name: String, details: [String: String] = [:], assertions: [RecordedAssertion] = []) {
        self.type = type
        self.name = name
        self.details = details
        self.assertions = assertions
    }
}

/// An assertion attached to a recorded action
struct RecordedAssertion {
    let type: String  // "visible", "text", "image_match", etc.
    let target: String
    let value: String
}

