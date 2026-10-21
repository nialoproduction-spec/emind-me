import AppKit
import Combine
import CoreServices
import Foundation

/// The pure part of the render ping: video files seen changing, and which
/// of them have stopped growing (a finished render). Tested on its own.
struct RenderTracker: Equatable {
    struct File: Equatable {
        var size: Int64
        /// When its size last changed.
        var changedAt: Date
        /// When it was first seen changing.
        var firstSeen: Date
        /// It got bigger at least once while watched (a render, not a stray touch).
        var grew = false
    }

    /// Quiet this long (no growth) = finished.
    static let settleAfter: TimeInterval = 12
    /// Only renders that took at least this long count (not a quick save).
    static let minimumDuration: TimeInterval = 4
    /// Forgotten if nothing happens for this long.
    static let forgetAfter: TimeInterval = 15 * 60

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "mxf", "avi", "mkv", "webm", "braw", "wav", "mp3", "aac", "m4a"]

    private(set) var files: [String: File] = [:]

    var isEmpty: Bool { files.isEmpty }

    static func isRenderFile(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix(".") else { return false }
        return videoExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// A file-system event for `path`: start watching it.
    mutating func touched(_ path: String, size: Int64, now: Date) {
        guard Self.isRenderFile(path) else { return }
        if var file = files[path] {
            if size != file.size {
                file.grew = file.grew || size > file.size
                file.size = size
                file.changedAt = now
            }
            files[path] = file
        } else {
            files[path] = File(size: size, changedAt: now, firstSeen: now)
        }
    }

    /// A size check. Returns the files that just finished.
    mutating func check(sizes: [String: Int64?], now: Date) -> [String] {
        var finished: [String] = []
        for (path, file) in files {
            guard let current = sizes[path] ?? nil else {
                files[path] = nil // gone (a temp file, or moved away)
                continue
            }
            var updated = file
            if current != file.size {
                updated.grew = updated.grew || current > file.size
                updated.size = current
                updated.changedAt = now
                files[path] = updated
                continue
            }
            let quiet = now.timeIntervalSince(file.changedAt)
            if quiet >= Self.settleAfter, file.grew, file.size > 0,
               file.changedAt.timeIntervalSince(file.firstSeen) >= Self.minimumDuration {
                finished.append(path)
                files[path] = nil
            } else if quiet >= Self.forgetAfter || (quiet >= Self.settleAfter && !file.grew) {
                files[path] = nil
            }
        }
        return finished.sorted()
    }
}

/// Watches the folders you render into (Settings → Smart → Render done
/// ping). A new video file that grows and then stops, while DaVinci Resolve
/// is open, gets a "Render done" popup with its name; if you're away it goes
/// on the "You missed" list instead. Uses FSEvents, so it costs nothing
/// while nothing is being written.
@MainActor
final class RenderWatcher {
    static let shared = RenderWatcher()

    private var stream: FSEventStreamRef?
    private var watching: [String] = []
    private var tracker = RenderTracker()
    private var checkTask: Task<Void, Never>?
    private let settings = AppSettings.renderWatch
    private var observer: Any?

    private init() {}

    func start() {
        observer = settings.$value.receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in self?.restart() }
        }
        restart()
    }

    /// DaVinci Resolve (or Resolve Studio) is open.
    static var resolveIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            let id = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            return id.contains("davinciresolve") || name.contains("davinci resolve")
        }
    }

    private func restart() {
        let value = settings.value
        let folders = value.isEnabled ? value.folders.filter { FileManager.default.fileExists(atPath: $0) } : []
        guard folders != watching else { return }
        stopStream()
        watching = folders
        guard !folders.isEmpty else { return }

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, renderEventCallback, &context, folders as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags)
        else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static func size(of path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
    }

    fileprivate func filesChanged(_ paths: [String]) {
        let now = Date()
        for path in paths where RenderTracker.isRenderFile(path) {
            tracker.touched(path, size: Self.size(of: path) ?? 0, now: now)
        }
        guard !tracker.isEmpty, checkTask == nil else { return }
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                if self.checkOnce() { self.checkTask = nil; return }
            }
        }
    }

    /// One size check; true once there's nothing left to watch.
    private func checkOnce() -> Bool {
        let now = Date()
        var sizes: [String: Int64?] = [:]
        for path in tracker.files.keys { sizes[path] = Self.size(of: path) }
        let finished = tracker.check(sizes: sizes, now: now)
        if !finished.isEmpty, Self.resolveIsRunning {
            for path in finished { announce(path, at: now) }
        }
        return tracker.isEmpty
    }

    private func announce(_ path: String, at date: Date) {
        let name = (path as NSString).lastPathComponent
        if AwayDetector.isAway() {
            ReminderScheduler.shared.noteMissed(title: "Render done", at: date, detail: name)
            return
        }
        NoticePillController.shared.show(NoticeContent(title: "Render done", detail: name, duration: 20,
                                                       mood: .done))
    }
}

/// FSEvents calls this on the main queue (see `FSEventStreamSetDispatchQueue`).
private func renderEventCallback(_ stream: ConstFSEventStreamRef, _ info: UnsafeMutableRawPointer?, _ count: Int,
                                 _ paths: UnsafeMutableRawPointer, _ flags: UnsafePointer<FSEventStreamEventFlags>,
                                 _ ids: UnsafePointer<FSEventStreamEventId>) {
    guard let info else { return }
    let array = unsafeBitCast(paths, to: NSArray.self)
    let changed = (0..<count).compactMap { array[$0] as? String }
    MainActor.assumeIsolated {
        Unmanaged<RenderWatcher>.fromOpaque(info).takeUnretainedValue().filesChanged(changed)
    }
}
