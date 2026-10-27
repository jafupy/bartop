import Combine
import Foundation

final class Monitor: ObservableObject {
    @Published var metrics = Metrics()
    @Published var cpuHistory: [Double] = []
    @Published var gpuHistory: [Double?] = []
    @Published var downloadHistory: [Double] = []
    @Published var uploadHistory: [Double] = []
    @Published var coreHistory: [[Double]] = []
    @Published var paused = false
    var dashboardVisible = false
    var onUpdate: (() -> Void)?
    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "com.jafupy.bartop.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var sampling = false
    private var generation = 0

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.collect() }
        timer.resume()
        self.timer = timer
    }

    func togglePause() {
        paused.toggle()
        generation += 1
        onUpdate?()
    }

    private func collect() {
        guard !paused, !sampling else { return }
        sampling = true
        let includeProcesses = dashboardVisible
        let generation = self.generation
        queue.async { [self] in
            let sample = sampler.read(includeProcesses: includeProcesses)
            DispatchQueue.main.async { [self] in
                sampling = false
                guard !paused, generation == self.generation else { return }
                metrics = sample
                cpuHistory = Array((cpuHistory + [sample.cpu]).suffix(180))
                gpuHistory = Array((gpuHistory + [sample.gpu]).suffix(180))
                downloadHistory = Array((downloadHistory + [sample.download]).suffix(180))
                uploadHistory = Array((uploadHistory + [sample.upload]).suffix(180))
                coreHistory = sample.cores.enumerated().map { index, usage in
                    let previous = index < coreHistory.count ? coreHistory[index] : []
                    return Array((previous + [usage]).suffix(180))
                }
                onUpdate?()
            }
        }
    }

    deinit { timer?.cancel() }
}
