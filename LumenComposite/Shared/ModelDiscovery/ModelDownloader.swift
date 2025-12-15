import Foundation
import Combine

class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0.0
    @Published var isDownloading = false
    @Published var currentFileName: String = ""
    
    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private var resumeData: Data?
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }
    
    func download(url: URL, to destination: URL) {
        self.currentFileName = url.lastPathComponent
        self.isDownloading = true
        self.progress = 0.0
        
        let task = session.downloadTask(with: url)
        task.resume()
        self.downloadTask = task
    }
    
    func cancel() {
        downloadTask?.cancel(byProducingResumeData: { data in
            self.resumeData = data
        })
        isDownloading = false
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let originalURL = downloadTask.originalRequest?.url else { return }
        let destinationURL = ModelStorage.shared.modelsURL.appendingPathComponent(originalURL.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            DispatchQueue.main.async {
                self.isDownloading = false
                self.progress = 1.0
            }
        } catch {
            print("File move error: \(error)")
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            self.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        }
    }
}
