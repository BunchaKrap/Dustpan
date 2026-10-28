import Darwin
import Foundation

/// One running process at the moment it was sampled. Read-only.
public struct RunningProcess: Identifiable, Hashable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    /// The kernel's short name (up to 16 characters); see `displayName` for the friendly one.
    public let shortName: String
    /// The program file, when macOS reveals it.
    public let path: String?
    public let uid: uid_t
    public let started: Date?
    /// CPU time used so far (user + system), in nanoseconds. Nil for processes of other users.
    public let cpuNanoseconds: UInt64?
    /// Memory as Activity Monitor's "Memory" column shows it. Nil for processes of other users.
    public let memoryBytes: Int64?

    public var id: Int32 { pid }

    public init(pid: Int32, parentPID: Int32, shortName: String, path: String?, uid: uid_t, started: Date?,
                cpuNanoseconds: UInt64?, memoryBytes: Int64?) {
        self.pid = pid
        self.parentPID = parentPID
        self.shortName = shortName
        self.path = path
        self.uid = uid
        self.started = started
        self.cpuNanoseconds = cpuNanoseconds
        self.memoryBytes = memoryBytes
    }

    /// The outermost `.app` bundle the program lives in, e.g. a helper inside Slack.app → Slack.app.
    public var appBundlePath: String? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    public var displayName: String {
        guard let path else { return shortName }
        let parts = path.split(separator: "/").map(String.init)
        guard let file = parts.last else { return shortName }
        // Tools that install each version as a file named after it (…/claude/versions/2.1.312) → "claude 2.1.312".
        if file.first?.isNumber == true,
           let owner = parts.dropLast().last(where: { !["versions", "bin", "current", "libexec"].contains($0) && $0.first?.isNumber != true }) {
            return "\(owner) \(file)"
        }
        return file
    }

    public var userName: String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return "\(uid)" }
        return String(cString: name)
    }

    /// True when the program file is gone, e.g. deleted or replaced while it was running.
    public var executableIsMissing: Bool {
        guard let path else { return false }
        return !FileManager.default.fileExists(atPath: path)
    }
}

public enum ProcessList {
    /// Every process on the Mac. Other users' processes (e.g. root daemons) come without CPU and memory figures.
    public static func snapshot() -> [RunningProcess] {
        kernelProcesses().compactMap { info -> RunningProcess? in
            let pid = info.kp_proc.p_pid
            guard pid > 0 else { return nil }
            let usage = resourceUsage(pid)
            let startedAt = info.kp_proc.p_un.__p_starttime
            return RunningProcess(
                pid: pid,
                parentPID: info.kp_eproc.e_ppid,
                shortName: withUnsafeBytes(of: info.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) },
                path: executablePath(pid),
                uid: info.kp_eproc.e_ucred.cr_uid,
                started: startedAt.tv_sec > 0 ? Date(timeIntervalSince1970: TimeInterval(startedAt.tv_sec)) : nil,
                cpuNanoseconds: usage?.cpu,
                memoryBytes: usage?.memory
            )
        }
    }

    /// The same list `ps` reads: all processes, any owner.
    private static func kernelProcesses() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return [] }
            // Room for processes started between the two calls.
            size += size / 8
            var list = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
            if sysctl(&mib, UInt32(mib.count), &list, &size, nil, 0) == 0 {
                return Array(list.prefix(size / MemoryLayout<kinfo_proc>.stride))
            }
            guard errno == ENOMEM else { return [] }
        }
        return []
    }

    public static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : launchPath(pid)
    }

    /// Fallback that `ps` also uses: the path the process was started with, stored before its arguments.
    private static func launchPath(_ pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let start = MemoryLayout<Int32>.size
        guard let end = buffer[start..<size].firstIndex(of: 0), end > start else { return nil }
        let path = String(decoding: buffer[start..<end], as: UTF8.self)
        return path.hasPrefix("/") ? path : nil
    }

    private static let ticksToNanoseconds: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    private static func resourceUsage(_ pid: Int32) -> (cpu: UInt64, memory: Int64)? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard result == 0 else { return nil }
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        return (UInt64(ticks * ticksToNanoseconds), Int64(info.ri_phys_footprint))
    }
}

/// Why a process couldn't be stopped, in words for the person using the app.
public enum ProcessStopError: Error, CustomStringConvertible, Sendable {
    case protected(String)
    case notPermitted
    case gone
    case failed(Int32)

    public var description: String {
        switch self {
        case .protected(let reason): reason
        case .notPermitted: "It runs as the system (root) or another user, so macOS doesn't let Dustpan stop it."
        case .gone: "It had already quit."
        case .failed(let code): "macOS refused (\(String(cString: strerror(code))))."
        }
    }
}

public enum ProcessControl {
    /// Processes whose loss logs you out, freezes the screen or stops the Mac working.
    public static let critical: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "logind", "opendirectoryd", "securityd",
        "configd", "notifyd", "UserEventAgent", "coreservicesd", "diskarbitrationd", "fseventsd", "powerd",
        "syslogd", "mds", "Dock", "SystemUIServer", "trustd", "tccd", "sandboxd", "kextd", "watchdogd",
    ]

    /// Explains why `process` must not be stopped, or nil when it may be.
    public static func protectionReason(for process: RunningProcess, selfPID: Int32 = getpid()) -> String? {
        if process.pid <= 1 { return "\(process.displayName) is the core of macOS. Stopping it would shut the Mac down." }
        if process.pid == selfPID { return "That's Dustpan itself. Use Dustpan › Quit Dustpan instead." }
        if critical.contains(process.displayName) || critical.contains(process.shortName) {
            return "\(process.displayName) keeps macOS running. Stopping it could log you out or freeze the screen."
        }
        return nil
    }

    /// Asks the process to quit (SIGTERM), or ends it immediately (SIGKILL) when `force` is set.
    public static func stop(_ process: RunningProcess, force: Bool) -> Result<Void, ProcessStopError> {
        if let reason = protectionReason(for: process) { return .failure(.protected(reason)) }
        guard kill(process.pid, force ? SIGKILL : SIGTERM) == 0 else {
            switch errno {
            case EPERM: return .failure(.notPermitted)
            case ESRCH: return .failure(.gone)
            case let code: return .failure(.failed(code))
            }
        }
        return .success(())
    }
}
