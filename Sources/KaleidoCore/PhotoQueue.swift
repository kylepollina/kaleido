import Foundation

/// Small deterministic RNG so shuffle behaviour can be tested.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Picks which photo comes next. Shuffle mode deals from a "bag": every photo is shown once before any
/// repeats, and the first photo of a new round is never the one that just played. Photos that are
/// disabled mid-round drop out; newly enabled ones are slotted into the remaining bag.
public final class PhotoQueue<ID: Hashable> {
    public var shuffle: Bool
    private var bag: [ID] = []
    private var known: Set<ID> = []
    private var rng: SplitMix64

    public init(shuffle: Bool, seed: UInt64 = UInt64.random(in: .min ... .max)) {
        self.shuffle = shuffle
        self.rng = SplitMix64(seed: seed)
    }

    /// `ids` are the currently enabled photos in library order; `current` is what is on screen.
    public func next(from ids: [ID], current: ID?) -> ID? {
        guard !ids.isEmpty else { bag = []; known = []; return nil }
        if ids.count == 1 { return ids[0] }

        guard shuffle else {
            guard let current, let i = ids.firstIndex(of: current) else { return ids[0] }
            return ids[(i + 1) % ids.count]
        }

        let idSet = Set(ids)
        bag.removeAll { !idSet.contains($0) }
        for id in ids where !known.contains(id) && !bag.contains(id) {
            bag.insert(id, at: Int.random(in: 0...bag.count, using: &rng))
        }
        known = idSet

        if bag.isEmpty {
            bag = ids
            bag.shuffle(using: &rng)
            if bag.last == current, bag.count > 1 {
                // The bag is dealt from the end: keep the photo that just played out of the first slot.
                let swap = Int.random(in: 0..<(bag.count - 1), using: &rng)
                bag.swapAt(swap, bag.count - 1)
            }
        }
        // Sequence within a round may still start with `current` if it was only just re-added; skip it.
        if bag.count > 1, bag.last == current { bag.swapAt(0, bag.count - 1) }
        return bag.removeLast()
    }

    public func reset() { bag = []; known = [] }
}
