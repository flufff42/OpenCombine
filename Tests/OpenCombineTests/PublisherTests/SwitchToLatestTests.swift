//
//  SwitchToLatestTests.swift
//  
//
//  Created by Sergej Jaskiewicz on 07.01.2020.
//

import XCTest

#if OPENCOMBINE_COMPATIBILITY_TEST
import Combine
#else
import OpenCombine
#endif

@available(macOS 10.15, iOS 13.0, *)
final class SwitchToLatestTests: XCTestCase {

    func testSwitchToLatestSequenceWithSink() {
        var history = [Int]()
        let cancellable = Publishers.Sequence<Range<Int>, Never>(sequence: 1 ..< 5)
            .map {
                Publishers.Sequence(sequence: $0 ..< $0 + 4)
            }
            .switchToLatest()
            .sink {
                history.append($0)
            }

        XCTAssertEqual(history, [1, 2, 3, 4, 2, 3, 4, 5, 3, 4, 5, 6, 4, 5, 6, 7])

        cancellable.cancel()
    }

    func testSendsChildValuesFromLatestOuterPublisher() {
        let upstreamPublisher = PassthroughSubject<
            PassthroughSubject<Int, TestingError>,
            TestingError>()
        let childPublisher1 = PassthroughSubject<Int, TestingError>()
        let childPublisher2 = PassthroughSubject<Int, TestingError>()

        let switchToLatest = upstreamPublisher.switchToLatest()

        let downstreamSubscriber = TrackingSubscriber(receiveSubscription: {
            $0.request(.unlimited)
        })

        switchToLatest.subscribe(downstreamSubscriber)

        upstreamPublisher.send(childPublisher1)
        upstreamPublisher.send(childPublisher2)

        childPublisher1.send(666)
        childPublisher2.send(777)
        childPublisher1.send(888)
        childPublisher2.send(999)
        XCTAssertEqual(downstreamSubscriber.history, [.subscription("SwitchToLatest"),
                                                      .value(777),
                                                      .value(999)])
    }

    func testCancelCancels() throws {
        typealias NestedPublisher = CustomPublisherBase<Int, Never>
        let upstreamSubscription = CustomSubscription()
        let upstreamPublisher = CustomPublisherBase<NestedPublisher, Never>(
            subscription: upstreamSubscription
        )

        let childSubscription = CustomSubscription()
        let childPublisher = NestedPublisher(subscription: childSubscription)

        let switchToLatest = upstreamPublisher.switchToLatest()

        var downstreamSubscription: Subscription?
        let tracking = TrackingSubscriberBase<Int, Never>(
            receiveSubscription: {
                downstreamSubscription = $0
                $0.request(.max(42))
            }
        )

        upstreamSubscription.onCancel = {
            XCTAssertEqual(childSubscription.history, [.requested(.max(42)),
                                                       .cancelled])
        }

        childSubscription.onCancel = {
            XCTAssertEqual(upstreamSubscription.history, [.requested(.unlimited)])
        }

        switchToLatest.subscribe(tracking)

        XCTAssertEqual(upstreamPublisher.send(childPublisher), .none)

        try XCTUnwrap(downstreamSubscription).cancel()

        XCTAssertEqual(upstreamSubscription.history, [.requested(.unlimited), .cancelled])
        XCTAssertEqual(childSubscription.history, [.requested(.max(42)), .cancelled])
    }
}
