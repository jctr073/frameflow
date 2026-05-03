struct PinnedCopyResult: Sendable {
    let copiedCount: Int
    let failures: [String]
}
