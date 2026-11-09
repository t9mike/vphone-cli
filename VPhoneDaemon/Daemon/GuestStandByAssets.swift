import Darwin
import Foundation

/// iOS 27's FaceSuggestions service asserts when MobileAsset cannot create
/// this directory on the hybrid guest (errno 89). Creating the ordinary
/// directory first lets ASEnsureDataVault succeed without changing Apple code.
/// This does not claim to implement the kernel's data-vault protection.
/// See Research/Guest/standby_gallery_hang.md.
enum GuestStandByAssets {
    static let service = "com.apple.duetexpertd"
    static let daemonPlist = "/System/Library/LaunchDaemons/com.apple.duetexpertd.plist"
    static let components = ["MobileAsset", "AssetsV2", "com_apple_MobileAsset_DuetExpertCenterAsset"]

    /// The startup caller also requires the owning daemon's plist. Leave other
    /// OS releases alone: their service lists and vault behavior differ.
    static func applies(iosMajor: Int, hasDaemon: Bool) -> Bool {
        iosMajor == 27 && hasDaemon
    }

    /// Descriptor-relative traversal refuses links and non-directories at
    /// every component. Never replace, chmod, chown or empty an existing store.
    @discardableResult
    static func prepare(varDirectory: String = "/private/var") throws -> Bool {
        var directory = open(varDirectory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw failure(varDirectory) }
        defer { close(directory) }
        var createdStore = false
        for component in components {
            var child = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if child < 0, errno == ENOENT {
                if mkdirat(directory, component, 0o755) == 0 {
                    createdStore = component == components.last
                } else if errno != EEXIST {
                    throw failure(component)
                }
                child = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard child >= 0 else { throw failure(component) }
            close(directory)
            directory = child
        }
        return createdStore
    }

    private static func failure(_ path: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: path])
    }
}
