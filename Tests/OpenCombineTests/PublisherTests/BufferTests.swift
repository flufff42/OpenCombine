//
//  BufferTests.swift
//  
//
//  Created by Sergej Jaskiewicz on 08.01.2020.
//

import XCTest

#if OPENCOMBINE_COMPATIBILITY_TEST
import Combine
#else
import OpenCombine
#endif

@available(macOS 10.15, iOS 13.0, *)
final class BufferTests: XCTestCase {

    func testInitialDemandWithKeepFullPrefetchStrategy() {
        BufferTests.testInitialDemand(
            withPrefetchStragety: .keepFull,
            expectedSubscriptionHistory: [.requested(.max(42))]
        )
    }

    func testInitialDemandWithByRequestPrefetchStrategy() {
        BufferTests.testInitialDemand(
            withPrefetchStragety: .byRequest,
            expectedSubscriptionHistory: [.requested(.unlimited)]
        )
    }

    func testBufferingInputDroppingNewest() throws {
        try BufferTests.testBufferingInput(whenFull: .dropNewest)
    }

    func testBufferingInputDroppingOldest() throws {
        try BufferTests.testBufferingInput(whenFull: .dropOldest)
    }

    func testBufferingInputFailingWhenBufferIsFull() throws {
        try BufferTests.testBufferingInput(whenFull: .customError { TestingError.oops })
    }

    func testReceiveValueAfterFinishing() throws {
        try BufferTests.testReceiveValueAfterCompleting(.finished)
    }

    func testReceiveValueAfterFailing() throws {
        try BufferTests.testReceiveValueAfterCompleting(.failure(.oops))
    }

    func testDeadlockWhenErroringOnFullBuffer() {
        var recursionCounter = 10
        let helper = OperatorTestHelper(
            publisherType: CustomPublisher.self,
            initialDemand: .max(2),
            receiveValueDemand: .none,
            createSut: { publisher in
                publisher.buffer(
                    size: 0,
                    prefetch: .keepFull,
                    whenFull: .customError {
                        if recursionCounter == 0 { return TestingError.oops }
                        recursionCounter -= 1
                        _ = publisher.send(1000)
                        return TestingError.oops
                    }
                )
            }
        )

        assertCrashes {
            _ = helper.publisher.send(0)
        }
    }

    func testBufferReflection() throws {
        try testReflection(
            parentInput: Int.self,
            parentFailure: TestingError.self,
            description: "Buffer",
            customMirror: expectedChildren(
                ("values", "[]"),
                ("state", .contains("ready(")),
                ("downstreamDemand", "max(0)"),
                ("terminal", "nil")
            ),
            playgroundDescription: "Buffer",
            { $0.buffer(size: 13, prefetch: .keepFull, whenFull: .dropNewest) }
        )
    }

    // MARK: - Generic tests

    private static func testInitialDemand(
        withPrefetchStragety prefetch: Publishers.PrefetchStrategy,
        expectedSubscriptionHistory: [CustomSubscription.Event]
    ) {
        let subscription = CustomSubscription()
        let publisher = CustomPublisher(subscription: nil)
        let tracking = TrackingSubscriber()

        subscription.onRequest = { _ in
            XCTAssertEqual(tracking.history, [])
        }

        let buffer = publisher
            .buffer(size: 42, prefetch: prefetch, whenFull: .dropOldest)

        buffer.subscribe(tracking)

        XCTAssertEqual(tracking.history, [])

        publisher.send(subscription: subscription)

        XCTAssertEqual(subscription.history, expectedSubscriptionHistory)
        XCTAssertEqual(tracking.history, [.subscription("Buffer")])
    }

    private static func testBufferingInput(
        whenFull: Publishers.BufferingStrategy<TestingError>
    ) throws {
        let helper = OperatorTestHelper(
            publisherType: CustomPublisher.self,
            initialDemand: nil,
            receiveValueDemand: .none,
            createSut: { $0.buffer(size: 3, prefetch: .byRequest, whenFull: whenFull) }
        )

        XCTAssertEqual(helper.tracking.history, [.subscription("Buffer")])
        XCTAssertEqual(helper.subscription.history, [.requested(.unlimited)])

        XCTAssertEqual(helper.publisher.send(1), .none)
        XCTAssertEqual(helper.publisher.send(2), .none)
        XCTAssertEqual(helper.publisher.send(3), .none)
        XCTAssertEqual(helper.publisher.send(4), .none)
        XCTAssertEqual(helper.publisher.send(5), .none)

        XCTAssertEqual(helper.tracking.history, [.subscription("Buffer")])
        switch whenFull {
        case .dropNewest, .dropOldest:
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited)])
        case .customError:
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                         .cancelled])
#if OPENCOMBINE_COMPATIBILITY_TEST
        @unknown default:
            fatalError("unreachable")
#endif
        }

        try XCTUnwrap(helper.downstreamSubscription).request(.max(3))

        switch whenFull {
        case .dropNewest:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .value(1),
                                                     .value(2),
                                                     .value(3)])
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                         .requested(.max(3))])
        case .dropOldest:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .value(3),
                                                     .value(4),
                                                     .value(5)])
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                         .requested(.max(3))])
        case .customError:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .value(1),
                                                     .value(2),
                                                     .value(3)])
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                         .cancelled,
                                                         .requested(.max(3))])
#if OPENCOMBINE_COMPATIBILITY_TEST
        @unknown default:
            fatalError("unreachable")
#endif
        }

        try XCTUnwrap(helper.downstreamSubscription).request(.max(1))

        switch whenFull {
        case .dropNewest:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .value(1),
                                                     .value(2),
                                                     .value(3)])
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                         .requested(.max(3)),
                                                         .requested(.max(1))])
        case .dropOldest:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .value(3),
                                                     .value(4),
                                                     .value(5)])
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                         .requested(.max(3)),
                                                         .requested(.max(1))])
        case .customError:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .value(1),
                                                     .value(2),
                                                     .value(3),
                                                     .completion(.failure(.oops))])
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                         .cancelled,
                                                         .requested(.max(3)),
                                                         .requested(.max(1))])
#if OPENCOMBINE_COMPATIBILITY_TEST
        @unknown default:
            fatalError("unreachable")
#endif
        }
    }

    private static func testReceiveValueAfterCompleting(
        _ completion: Subscribers.Completion<TestingError>
    ) throws {
        let helper = OperatorTestHelper(
            publisherType: CustomPublisher.self,
            initialDemand: nil,
            receiveValueDemand: .none,
            createSut: { $0.buffer(size: 3, prefetch: .byRequest, whenFull: .dropOldest) }
        )

        helper.publisher.send(completion: completion)

        XCTAssertEqual(helper.tracking.history, [.subscription("Buffer")])
        XCTAssertEqual(helper.subscription.history, [.requested(.unlimited)])

        XCTAssertEqual(helper.publisher.send(1), .none)
        XCTAssertEqual(helper.publisher.send(2), .none)

        XCTAssertEqual(helper.tracking.history, [.subscription("Buffer")])
        XCTAssertEqual(helper.subscription.history, [.requested(.unlimited)])

        try XCTUnwrap(helper.downstreamSubscription).request(.max(2))

        switch completion {
        case .finished:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .value(1),
                                                     .value(2)])
        case .failure:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .completion(completion)])
        }

        XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                     .requested(.max(2))])

        try XCTUnwrap(helper.downstreamSubscription).request(.max(1))

        switch completion {
        case .finished:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .value(1),
                                                     .value(2),
                                                     .completion(completion)])
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                         .requested(.max(2)),
                                                         .requested(.max(1))])
        case .failure:
            XCTAssertEqual(helper.tracking.history, [.subscription("Buffer"),
                                                     .completion(completion)])
            XCTAssertEqual(helper.subscription.history, [.requested(.unlimited),
                                                         .requested(.max(2))])
        }
    }
}
