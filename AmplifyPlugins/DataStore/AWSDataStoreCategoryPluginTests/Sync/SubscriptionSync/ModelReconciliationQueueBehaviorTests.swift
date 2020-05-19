//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest

@testable import Amplify
@testable import AmplifyTestCommon
@testable import AWSDataStoreCategoryPlugin
@testable import AWSPluginsCore

class ModelReconciliationQueueBehaviorTests: ReconciliationQueueTestBase {

    /// - Given: A new AWSModelReconciliationQueue
    /// - When:
    ///    - I publish incoming events
    /// - Then:
    ///    - The queue does not process them
    func testBuffersBeforeStart() throws {
        let eventsNotSaved = expectation(description: "Events not saved")
        eventsNotSaved.isInverted = true
        storageAdapter.responders[.saveUntypedModel] = SaveUntypedModelResponder { _, _ in
            eventsNotSaved.fulfill()
        }

        let queue = AWSModelReconciliationQueue(modelType: MockSynced.self,
                                                storageAdapter: storageAdapter,
                                                api: apiPlugin,
                                                auth: authPlugin,
                                                incomingSubscriptionEvents: subscriptionEventsPublisher)

        // We know this won't be nil, but we need to keep a reference to the queue in memory for the duration of the
        // test, and since we don't act on it otherwise, Swift warns about queue never being used.
        XCTAssertNotNil(queue)

        for iteration in 1 ... 3 {
            let model = try MockSynced(id: "id-\(iteration)").eraseToAnyModel()
            let syncMetadata = MutationSyncMetadata(id: model.id,
                                                    deleted: false,
                                                    lastChangedAt: Date().unixSeconds,
                                                    version: 1)
            let mutationSync = MutationSync(model: model, syncMetadata: syncMetadata)
            subscriptionEventsSubject.send(.mutationEvent(mutationSync))
        }

        wait(for: [eventsNotSaved], timeout: 5.0)
    }

    /// - Given: An AWSModelReconciliationQueue that has been buffering events
    /// - When:
    ///    - I `start()` the queue
    /// - Then:
    ///    - It processes buffered events in order
    func testProcessesBufferedEvents() throws {
        let event1Saved = expectation(description: "Event 1 saved")
        let event2Saved = expectation(description: "Event 2 saved")
        let event3Saved = expectation(description: "Event 3 saved")
        storageAdapter.responders[.saveUntypedModel] = SaveUntypedModelResponder { model, completion in
            switch model.id {
            case "id-1":
                event1Saved.fulfill()
            case "id-2":
                event2Saved.fulfill()
            case "id-3":
                event3Saved.fulfill()
            default:
                break
            }

            completion(.success(model))
        }

        let queue = AWSModelReconciliationQueue(modelType: MockSynced.self,
                                                storageAdapter: storageAdapter,
                                                api: apiPlugin,
                                                auth: authPlugin,
                                                incomingSubscriptionEvents: subscriptionEventsPublisher)

        for iteration in 1 ... 3 {
            let model = try MockSynced(id: "id-\(iteration)").eraseToAnyModel()
            let syncMetadata = MutationSyncMetadata(id: model.id,
                                                    deleted: false,
                                                    lastChangedAt: Date().unixSeconds,
                                                    version: 1)
            let mutationSync = MutationSync(model: model, syncMetadata: syncMetadata)
            subscriptionEventsSubject.send(.mutationEvent(mutationSync))
        }

        queue.start()

        wait(for: [event1Saved, event2Saved, event3Saved], timeout: 5.0, enforceOrder: true)
    }

    /// - Given: An AWSModelReconciliationQueue that has been buffering events
    /// - When:
    ///    - I `start()` the queue
    /// - Then:
    ///    - It processes buffered events one at a time
    func testProcessesBufferedEventsSerially() throws {
        // This test relies on knowledge of the Reconciliation queue's internal behavior: specifically, that it saves
        // an event's metadata as the last step.

        let event1State = AtomicValue(initialValue: EventState.notStarted)
        let event2State = AtomicValue(initialValue: EventState.notStarted)
        let event3State = AtomicValue(initialValue: EventState.notStarted)

        // Return a successful MockSynced save
        storageAdapter.responders[.saveUntypedModel] = SaveUntypedModelResponder { model, completion in
            completion(.success(model))
        }

        // Return a successful MutationSyncMetadata save, and also assert the event states
        let allEventsProcessed = expectation(description: "All events processed")
        storageAdapter.responders[.saveModelCompletion] =
            SaveModelCompletionResponder<MutationSyncMetadata> { model, completion in
                switch model.id {
                case "id-1":
                    XCTAssertEqual(event1State.get(), .notStarted)
                    XCTAssertEqual(event2State.get(), .notStarted)
                    XCTAssertEqual(event3State.get(), .notStarted)
                    event1State.set(.finished)
                    event2State.set(.processing)
                case "id-2":
                    XCTAssertEqual(event1State.get(), .finished)
                    XCTAssertEqual(event2State.get(), .processing)
                    XCTAssertEqual(event3State.get(), .notStarted)
                    event2State.set(.finished)
                    event3State.set(.processing)
                case "id-3":
                    XCTAssertEqual(event1State.get(), .finished)
                    XCTAssertEqual(event2State.get(), .finished)
                    XCTAssertEqual(event3State.get(), .processing)
                    event3State.set(.finished)
                    allEventsProcessed.fulfill()
                default:
                    break
                }
                completion(.success(model))
        }

        let queue = AWSModelReconciliationQueue(modelType: MockSynced.self,
                                                storageAdapter: storageAdapter,
                                                api: apiPlugin,
                                                auth: authPlugin,
                                                incomingSubscriptionEvents: subscriptionEventsPublisher)
        for iteration in 1 ... 3 {
            let model = try MockSynced(id: "id-\(iteration)").eraseToAnyModel()
            let syncMetadata = MutationSyncMetadata(id: model.id,
                                                    deleted: false,
                                                    lastChangedAt: Date().unixSeconds,
                                                    version: 1)
            let mutationSync = MutationSync(model: model, syncMetadata: syncMetadata)
            subscriptionEventsSubject.send(.mutationEvent(mutationSync))
        }

        queue.start()

        wait(for: [allEventsProcessed], timeout: 5.0)
    }

    /// - Given: A started AWSModelReconciliationQueue with no pending events
    /// - When:
    ///    - I submit a new event
    /// - Then:
    ///    - The new event immediately processes
    func testProcessesNewEvents() throws {
        // Return a successful MockSynced save
        storageAdapter.responders[.saveUntypedModel] = SaveUntypedModelResponder { model, completion in
            completion(.success(model))
        }

        let event1ShouldBeProcessed = expectation(description: "Event 1 should be processed")
        let event2ShouldBeProcessed = expectation(description: "Event 2 should be processed")
        storageAdapter.responders[.saveModelCompletion] =
            SaveModelCompletionResponder<MutationSyncMetadata> { model, completion in
                switch model.id {
                case "id-1":
                    event1ShouldBeProcessed.fulfill()
                case "id-2":
                    event2ShouldBeProcessed.fulfill()
                default:
                    break
                }
                completion(.success(model))
        }

        let queue = AWSModelReconciliationQueue(modelType: MockSynced.self,
                                                storageAdapter: storageAdapter,
                                                api: apiPlugin,
                                                auth: authPlugin,
                                                incomingSubscriptionEvents: subscriptionEventsPublisher)
        for iteration in 1 ... 2 {
            let model = try MockSynced(id: "id-\(iteration)").eraseToAnyModel()
            let syncMetadata = MutationSyncMetadata(id: model.id,
                                                    deleted: false,
                                                    lastChangedAt: Date().unixSeconds,
                                                    version: 1)
            let mutationSync = MutationSync(model: model, syncMetadata: syncMetadata)
            subscriptionEventsSubject.send(.mutationEvent(mutationSync))
        }

        queue.start()

        wait(for: [event1ShouldBeProcessed, event2ShouldBeProcessed], timeout: 1.0)

        let event1ShouldNotBeProcessed = expectation(description: "Event 1 should not be processed")
        event1ShouldNotBeProcessed.isInverted = true
        let event2ShouldNotBeProcessed = expectation(description: "Event 2 should not be processed")
        event2ShouldNotBeProcessed.isInverted = true
        let event3ShouldBeProcessed = expectation(description: "Event 3 should not be processed")
        storageAdapter.responders[.saveModelCompletion] =
            SaveModelCompletionResponder<MutationSyncMetadata> { model, completion in
                switch model.id {
                case "id-1":
                    event1ShouldNotBeProcessed.fulfill()
                case "id-2":
                    event2ShouldNotBeProcessed.fulfill()
                case "id-3":
                    event3ShouldBeProcessed.fulfill()
                default:
                    break
                }
                completion(.success(model))
        }

        let model = try MockSynced(id: "id-3").eraseToAnyModel()
        let syncMetadata = MutationSyncMetadata(id: model.id,
                                                deleted: false,
                                                lastChangedAt: Date().unixSeconds,
                                                version: 1)
        let mutationSync = MutationSync(model: model, syncMetadata: syncMetadata)
        subscriptionEventsSubject.send(.mutationEvent(mutationSync))

        wait(for: [event1ShouldNotBeProcessed, event2ShouldNotBeProcessed, event3ShouldBeProcessed], timeout: 1.0)

    }

}

enum EventState {
    case notStarted
    case processing
    case finished
}
