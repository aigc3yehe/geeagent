import Foundation

/// Mirrors `execution_runtime::tool::ToolRequest`. The frontend fills in the
/// tool id, arguments, and (when replaying after approval) an approval token.
/// `allowed_tool_ids` is intentionally omitted here: the backend always
/// resolves the persona allow-list from its own snapshot so a misbehaving UI
/// can't elevate a persona's permissions.
struct ToolInvocation: Hashable, Sendable {
    var toolID: String
    var arguments: [String: WorkbenchToolArgumentValue]
    var approvalToken: String?

    init(toolID: String, arguments: [String: WorkbenchToolArgumentValue] = [:], approvalToken: String? = nil) {
        self.toolID = toolID
        self.arguments = arguments
        self.approvalToken = approvalToken
    }
}

/// A tiny JSON-shaped argument value. We purposefully do not reuse
/// `JSONSerialization`'s `Any` in our public API because `Hashable` and
/// `Equatable` on `Any` is a mess.
indirect enum WorkbenchToolArgumentValue: Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
    case object([String: WorkbenchToolArgumentValue])
    case null
}

/// Blast-radius classification passed through from the backend catalog. Used
/// by the approval sheet to tone the copy.
enum WorkbenchToolBlastRadius: String, Codable, Hashable {
    case safe
    case local
    case external
}

/// Mirrors `execution_runtime::tool::ToolOutcome`.
enum WorkbenchToolOutcome: Hashable {
    case completed(toolID: String, payload: [String: Any])
    case needsApproval(toolID: String, blastRadius: WorkbenchToolBlastRadius, prompt: String)
    case denied(toolID: String, reason: String)
    case error(toolID: String, code: String, message: String)

    var toolID: String {
        switch self {
        case let .completed(toolID, _),
             let .needsApproval(toolID, _, _),
             let .denied(toolID, _),
             let .error(toolID, _, _):
            return toolID
        }
    }

    static func == (lhs: WorkbenchToolOutcome, rhs: WorkbenchToolOutcome) -> Bool {
        switch (lhs, rhs) {
        case let (.completed(lt, lp), .completed(rt, rp)):
            return lt == rt && NSDictionary(dictionary: lp).isEqual(to: rp)
        case let (.needsApproval(lt, lb, lp), .needsApproval(rt, rb, rp)):
            return lt == rt && lb == rb && lp == rp
        case let (.denied(lt, lr), .denied(rt, rr)):
            return lt == rt && lr == rr
        case let (.error(lt, lc, lm), .error(rt, rc, rm)):
            return lt == rt && lc == rc && lm == rm
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .completed(toolID, payload):
            hasher.combine(0)
            hasher.combine(toolID)
            hasher.combine(NSDictionary(dictionary: payload))
        case let .needsApproval(toolID, blastRadius, prompt):
            hasher.combine(1)
            hasher.combine(toolID)
            hasher.combine(blastRadius)
            hasher.combine(prompt)
        case let .denied(toolID, reason):
            hasher.combine(2)
            hasher.combine(toolID)
            hasher.combine(reason)
        case let .error(toolID, code, message):
            hasher.combine(3)
            hasher.combine(toolID)
            hasher.combine(code)
            hasher.combine(message)
        }
    }
}

extension WorkbenchToolOutcome {
    /// Extracts the navigation intent encoded by `navigate.openSection` /
    /// `navigate.openModule`. Returns `nil` when the outcome is not a
    /// completion or doesn't carry an intent payload.
    var navigationIntent: WorkbenchToolNavigationIntent? {
        guard case let .completed(_, payload) = self else { return nil }
        guard let intent = payload["intent"] as? String else { return nil }
        switch intent {
        case "navigate.section":
            guard let rawSection = payload["section"] as? String,
                  let section = WorkbenchSection(rawValue: rawSection)
            else { return nil }
            return .section(section)
        case "navigate.module":
            guard let moduleID = payload["module_id"] as? String, !moduleID.isEmpty else { return nil }
            return .module(id: moduleID)
        default:
            return nil
        }
    }
}

enum WorkbenchToolNavigationIntent: Hashable {
    case section(WorkbenchSection)
    case module(id: String)
}

/// Represents an approval the user needs to accept before a tool can run. The
/// `generatedToken` is created by the store when the `NeedsApproval` outcome
/// arrives and is re-attached to the invocation on accept.
struct PendingToolApproval: Hashable {
    var invocation: ToolInvocation
    var blastRadius: WorkbenchToolBlastRadius
    var prompt: String
    var generatedToken: String
}

struct WorkbenchHostActionCompletion: Codable, Hashable, Sendable {
    var hostActionID: String
    var toolID: String
    var status: String
    var summary: String?
    var error: String?
    var resultJSON: String?

    enum CodingKeys: String, CodingKey {
        case hostActionID = "host_action_id"
        case toolID = "tool_id"
        case status
        case summary
        case error
        case resultJSON = "result_json"
    }
}

/// Helper that converts `ToolInvocation.arguments` into the `[String: Any]`
/// form `JSONSerialization` expects. Kept small and side-effect-free so the
/// Agent runtime can stay a thin transport.
enum WorkbenchToolArgumentCodec {
    static func encode(_ arguments: [String: WorkbenchToolArgumentValue]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in arguments {
            switch value {
            case let .string(string):
                out[key] = string
            case let .int(int):
                out[key] = int
            case let .double(double):
                out[key] = double
            case let .bool(bool):
                out[key] = bool
            case let .stringArray(array):
                out[key] = array
            case let .object(object):
                out[key] = encode(object)
            case .null:
                out[key] = NSNull()
            }
        }
        return out
    }
}
