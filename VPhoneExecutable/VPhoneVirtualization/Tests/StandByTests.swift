import Foundation

enum VPhoneLocalization { static let bundle = Bundle.main }
struct VPhoneGuestToolStatus { let message: String; let isError: Bool }
enum VPhoneControlsModel { static func guestMessage(_ error: Error) -> String { error.localizedDescription } }

@MainActor
final class VPhoneGuestControl {
    enum ControlError: Error { case unsupportedCapability(String), guestError(String), protocolError(String) }
    var isConnected = true
    var guestCapabilities = ["device_pose", "display_standby"]
    var foldRequestsInFlight = 0
    var foldSweepSeconds = 0.0
    var foldPosition: VPhoneFoldPosition?
    var foldAngle: Double?
    var transport: @MainActor (String, [String: Any]) async throws -> [String: Any]
    init(_ transport: @escaping @MainActor (String, [String: Any]) async throws -> [String: Any]) { self.transport = transport }
    func call(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        try await transport(method, params)
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
    func double(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func object(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
}

@main @MainActor
struct StandByTests {
    @MainActor final class GuestState {
        var actual = "off"
        var loseReply = false
    }

    static func main() async throws {
        let state = GuestState()
        let control = VPhoneGuestControl { method, params in
            if method == "display.posture" {
                state.actual = "off"
                return ["angle": 180.0, "hinge": 3, "hinge_hid": ["provider_running": true, "applied": true]]
            }
            precondition(method == "display.standby")
            if let requested = params["mode"] as? String {
                state.actual = requested
                if state.loseReply { throw VPhoneGuestControl.ControlError.guestError("reply lost") }
            }
            return ["mode": state.actual, "pose": ["available": true]]
        }
        let model = VPhoneFoldModel(control: control)
        await model.setStandBy(.tent)
        precondition(model.standByMode == .tent && model.status?.isError == false)
        precondition(control.foldAngle == 100 && control.foldRequestsInFlight == 0)
        await model.setStandBy(.book)
        precondition(model.standByMode == .book && control.foldAngle == 180)
        await model.set(.open)
        precondition(model.standByMode == .off && model.status?.isError == false)

        // A lost reply does not prove the guest rejected a mutation. Read back.
        state.loseReply = true
        await model.setStandBy(.tent)
        precondition(model.standByMode == .tent && model.status?.isError == true && !model.isSending)
        precondition(control.foldRequestsInFlight == 0)

        // A successful transport with contradictory readback must fail.
        control.transport = { _, _ in ["mode": "off", "pose": ["available": true]] }
        await model.setStandBy(.book)
        precondition(model.standByMode == .off && model.status?.isError == true)
        control.transport = { _, _ in ["mode": "book", "pose": ["available": false]] }
        do { _ = try await control.setStandByMode(.book); fatalError("accepted unavailable pose") } catch {}
        let unavailable = try await control.readStandByMode()
        precondition(unavailable == nil)
        precondition(control.foldRequestsInFlight == 0)

        // Old guests must not receive an unsupported mutation.
        control.guestCapabilities = ["device_pose"]
        control.transport = { _, _ in fatalError("called an old guest") }
        await model.setStandBy(.tent)
        precondition(!model.isSending && !model.supportsStandBy)
        do { _ = try await control.setStandByMode(.tent); fatalError("accepted unsupported capability") } catch {}

        // The title-bar fold action and panel share the same exclusion guard.
        control.guestCapabilities = ["device_pose", "display_standby"]
        control.foldRequestsInFlight = 1
        do { _ = try await control.setStandByMode(.tent); fatalError("overlapped StandBy") } catch {}
        do { _ = try await control.setFoldPosition(.closed, duration: 0); fatalError("overlapped fold") } catch {}
        precondition(control.foldRequestsInFlight == 1)
        print("StandBy tests passed: modes, normal fold, lost reply, invalid readback, old guest, overlapping transitions")
    }
}
