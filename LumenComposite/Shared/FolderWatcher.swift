import Foundation
import Combine

#if os(macOS)
import CoreServices
#endif

/// A platform-agnostic folder watcher that uses the most efficient native API available.
/// - macOS: Uses `FSEvents` for deep, recursive monitoring of directory trees.
/// - iOS: Uses `DispatchSource` for shallow directory monitoring (best available).
public final class FolderWatcher {
    private let url: URL
    private var streamContinuation: AsyncStream<Void>.Continuation?
    
    // Debounce logic
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 1.0
    private let queue = DispatchQueue(label: "com.lumen.folderwatcher", attributes: .concurrent)
    
    #if os(macOS)
    private var eventStream: FSEventStreamRef?
    #else
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    #endif
    
    public init(url: URL) {
        self.url = url
    }
    
    deinit {
        stopMonitoring()
    }
    
    /// Returns an async stream of change events.
    /// The stream yields a void value whenever a change is detected (debounced).
    public func events() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.streamContinuation = continuation
            self.startMonitoring()
            
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopMonitoring()
            }
        }
    }
    
    private func startMonitoring() {
        #if os(macOS)
        startFSEvents()
        #else
        startDispatchSource()
        #endif
    }
    
    public func stopMonitoring() {
        #if os(macOS)
        stopFSEvents()
        #else
        stopDispatchSource()
        #endif
        debounceTimer?.invalidate()
        debounceTimer = nil
    }
    
    private func notifyChange() {
        // Debounce on the main queue to ensure thread safety for the timer
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.debounceTimer?.invalidate()
            self.debounceTimer = Timer.scheduledTimer(withTimeInterval: self.debounceInterval, repeats: false) { _ in
                self.streamContinuation?.yield(())
            }
        }
    }
}

// MARK: - macOS Implementation (FSEvents)
#if os(macOS)
extension FolderWatcher {
    private func startFSEvents() {
        guard eventStream == nil else { return }
        
        let path = url.path as CFString
        let pathsToWatch = [path] as CFArray
        
        // FSEvents context to pass 'self' to the callback
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        // Create the stream
        // kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
                watcher.notifyChange()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // Latency (coalescing at the OS level)
            flags
        ) else {
            print("FolderWatcher: Failed to create FSEventStream for \(url.path)")
            return
        }
        
        self.eventStream = stream
        
        // Schedule on the dispatch queue (modern replacement for RunLoop)
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        
        print("FolderWatcher: Started FSEvents monitoring for \(url.path)")
    }
    
    private func stopFSEvents() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }
}
#endif

// MARK: - iOS Implementation (DispatchSource)
#if !os(macOS)
extension FolderWatcher {
    private func startDispatchSource() {
        guard fileDescriptor == -1 else { return }
        
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            print("FolderWatcher: Failed to open \(url.path)")
            return
        }
        
        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .link, .rename, .delete, .extend, .attrib],
            queue: queue
        )
        
        dispatchSource?.setEventHandler { [weak self] in
            self?.notifyChange()
        }
        
        dispatchSource?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
            self.dispatchSource = nil
        }
        
        dispatchSource?.resume()
        print("FolderWatcher: Started DispatchSource monitoring for \(url.path)")
    }
    
    private func stopDispatchSource() {
        dispatchSource?.cancel()
    }
}
#endif
