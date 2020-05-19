//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import XCTest

@testable import Amplify
@testable import AmplifyTestCommon
@testable import AWSPluginsCore
@testable import AWSDataStoreCategoryPlugin


class AWSIncomingEventReconciliationQueueTests: XCTestCase {
    var storageAdapter: MockSQLiteStorageEngineAdapter!
    var apiPlugin: MockAPICategoryPlugin!

    override func setUp() {
        MockModelReconciliationQueue.reset()
        storageAdapter = MockSQLiteStorageEngineAdapter()
        storageAdapter.returnOnQuery(dataStoreResult: .none)
        storageAdapter.returnOnSave(dataStoreResult: .none)

        apiPlugin = MockAPICategoryPlugin()

    }
    var operationQueue: OperationQueue!

    //This test case attempts to hit a race condition, and may be required to execute multiple times
    // in order to demonstrate the bug
    func testTwoConnectionStatusUpdatesAtSameTime() {
        let expectInitialized = expectation(description: "eventQueue expected to send out initialized state")

        let modelReconciliationQueueFactory
            = MockModelReconciliationQueue.init(modelType:storageAdapter:api:auth:incomingSubscriptionEvents:)
        let eventQueue = AWSIncomingEventReconciliationQueue(
            modelTypes: [Post.self, Comment.self],
            api: apiPlugin,
            storageAdapter: storageAdapter,
            modelReconciliationQueueFactory: modelReconciliationQueueFactory)
        eventQueue.start()

        let eventSync = eventQueue.publisher.sink(receiveCompletion: { _ in
            XCTFail("Not expecting this to call")
        }, receiveValue: { event  in
            switch event {
            case .initialized:
                expectInitialized.fulfill()
            default:
                XCTFail("Should not expect any other state")
            }
        })

        operationQueue = OperationQueue()
        operationQueue.name = "com.amazonaws.DataStore.UnitTestQueue"
        operationQueue.maxConcurrentOperationCount = 2
        operationQueue.underlyingQueue = DispatchQueue.global()
        operationQueue.isSuspended = true

        let reconciliationQueues = MockModelReconciliationQueue.mockModelReconciliationQueues
        for (queueName, queue) in reconciliationQueues {
            let cancellableOperation = CancelAwareBlockOperation {
                queue.modelReconciliationQueueSubject.send(.connected(queueName))
            }
            operationQueue.addOperation(cancellableOperation)
        }
        operationQueue.isSuspended = false
        waitForExpectations(timeout: 2)

    }
}

