import Foundation

public struct SpeedSample: Identifiable, Hashable, Sendable {
    public var date: Date
    public var download: Int
    public var upload: Int

    public init(date: Date, download: Int, upload: Int) {
        self.date = date
        self.download = download
        self.upload = upload
    }

    public var id: Date { date }
}

/// A fixed-size window of one-second speed samples for the Speed tab.
public struct SpeedHistory: Sendable {
    public private(set) var samples: [SpeedSample] = []
    public let capacity: Int

    public init(capacity: Int = 300) {
        self.capacity = capacity
    }

    public mutating func append(_ sample: SpeedSample) {
        samples.append(sample)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    public mutating func reset() {
        samples.removeAll()
    }
}
