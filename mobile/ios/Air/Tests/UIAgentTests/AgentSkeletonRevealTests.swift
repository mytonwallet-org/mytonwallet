import XCTest
import UIKit
@testable import UIAgent
@testable import UIComponents
import WalletResources

final class AgentSkeletonRevealTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    @MainActor
    func testConsecutiveAnswersKeepTheirOrderThroughoutTheLoadingMorph() throws {
        let fixture = RevealFixture(heights: [104, 264, 88], outgoing: [true, false, false])
        let window = makeKeyWindow(showing: fixture)
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let collection = fixture.collection
        let sources = fixture.placeholders()
        AgentSkeletonReveal.revealRows(in: collection, isRightToLeft: false, placeholders: sources) { _, index in
            .bubble(isOutgoing: fixture.outgoing[index.item])
        }
        let cells = collection.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(cells.count, 3)
        var motions: [(source: CGRect, target: CGRect, animation: CABasicAnimation)] = []
        for cell in cells {
            let bubble = cell.contentView
            let animation = try XCTUnwrap(bubble.layer.animation(forKey: "agentSkeletonReveal.geometry") as? CABasicAnimation)
            let value = try XCTUnwrap(animation.fromValue as? NSValue)
            let target = bubble.convert(bubble.bounds, to: collection)
            let source = CGRect(x: -target.width / 2, y: -target.height / 2, width: target.width, height: target.height)
                .applying(CATransform3DGetAffineTransform(value.caTransform3DValue))
                .offsetBy(dx: target.midX, dy: target.midY)
            motions.append((source, target, animation))
        }
        let expectedSources = sources.map { collection.convert($0.frame, from: nil) }.sorted { $0.minY < $1.minY }
        for (motion, expected) in zip(motions, expectedSources) {
            XCTAssertEqual(motion.source.minY, expected.minY, accuracy: 0.01)
            XCTAssertEqual(motion.source.height, expected.height, accuracy: 0.01)
            XCTAssertEqual(motion.animation.duration, AgentSkeletonReveal.duration)
            XCTAssertEqual(motion.animation.beginTime, try XCTUnwrap(motions.first).animation.beginTime, accuracy: 0.001)
            XCTAssertEqual(motion.animation.timingFunction, motions.first?.animation.timingFunction)
        }
        // Each layer has the same curve and start time, so the interpolation of both edges must preserve every gap.
        for progress in stride(from: CGFloat(0), through: 1, by: 0.125) {
            let frames = motions.map { motion in
                CGRect(
                    x: motion.source.minX + (motion.target.minX - motion.source.minX) * progress,
                    y: motion.source.minY + (motion.target.minY - motion.source.minY) * progress,
                    width: motion.source.width + (motion.target.width - motion.source.width) * progress,
                    height: motion.source.height + (motion.target.height - motion.source.height) * progress
                )
            }
            for (upper, lower) in zip(frames, frames.dropFirst()) {
                XCTAssertLessThanOrEqual(upper.maxY, lower.minY, "Rows overlap at progress \(progress)")
            }
        }
    }

    @MainActor
    func testUnusedPlaceholdersMoveAboveTheRealColumnAndAreRemoved() async throws {
        let fixture = RevealFixture(heights: [264, 88], outgoing: [false, false])
        let window = makeKeyWindow(showing: fixture)
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let collection = fixture.collection
        AgentSkeletonReveal.revealRows(in: collection, isRightToLeft: false, placeholders: fixture.placeholders()) { _, _ in
            .bubble(isOutgoing: false)
        }
        let surplus = try XCTUnwrap(collection.subviews.compactMap { $0 as? AgentBubbleBackgroundView }.first)
        let movement = try XCTUnwrap(surplus.layer.animation(forKey: "agentSkeletonReveal.surplus") as? CABasicAnimation)
        let from = try XCTUnwrap(movement.fromValue as? NSValue).cgPointValue
        let to = try XCTUnwrap(movement.toValue as? NSValue).cgPointValue
        let topRow = try XCTUnwrap(collection.visibleCells.min { $0.frame.minY < $1.frame.minY })
        XCTAssertLessThan(to.y, from.y)
        XCTAssertLessThanOrEqual(to.y + surplus.bounds.height / 2, topRow.frame.minY)
        XCTAssertEqual(movement.duration, AgentSkeletonReveal.duration)
        XCTAssertEqual(surplus.layer.animation(forKey: "agentSkeletonReveal.opacity")?.duration, movement.duration)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(surplus.superview)
        XCTAssertFalse(collection.subviews.contains { $0 is AgentBubbleBackgroundView })
    }
}

@MainActor
private final class RevealFixture: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    let heights: [CGFloat]
    let outgoing: [Bool]
    let collection: UICollectionView

    init(heights: [CGFloat], outgoing: [Bool]) {
        self.heights = heights
        self.outgoing = outgoing
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = AgentVCLayout.rowSpacing
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collection.frame = CGRect(x: 0, y: 100, width: 402, height: 700)
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "bubble")
        collection.dataSource = self
        collection.delegate = self
        view.addSubview(collection)
        collection.reloadData()
    }

    func placeholders() -> [AgentMessagesSkeletonView.Placeholder] {
        [
            .init(frame: collection.convert(CGRect(x: 16, y: 500, width: 344, height: 184), to: nil), isOutgoing: false),
            .init(frame: collection.convert(CGRect(x: 105, y: 364, width: 281, height: 120), to: nil), isOutgoing: true),
            .init(frame: collection.convert(CGRect(x: 16, y: 164, width: 360, height: 184), to: nil), isOutgoing: false),
        ]
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { heights.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "bubble", for: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: collectionView.bounds.width - 32, height: heights[indexPath.item])
    }
}
