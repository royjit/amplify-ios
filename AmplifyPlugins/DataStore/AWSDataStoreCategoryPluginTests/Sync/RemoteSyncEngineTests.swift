//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest
import SQLite

import Combine
@testable import Amplify
@testable import AmplifyTestCommon
@testable import AWSDataStoreCategoryPlugin

class RemoteSyncEngineTests: XCTestCase {
    var apiPlugin: MockAPICategoryPlugin!
    var authPlugin: MockAuthCategoryPlugin!

    var amplifyConfig: AmplifyConfiguration!
    var storageAdapter: StorageEngineAdapter!
    var remoteSyncEngine: RemoteSyncEngine!
    var mockRequestRetryablePolicy: MockRequestRetryablePolicy!

    let defaultAsyncWaitTimeout = 2.0

    override func setUp() {
        super.setUp()
        MockAWSInitialSyncOrchestrator.reset()
        storageAdapter = MockSQLiteStorageEngineAdapter()
        let mockOutgoingMutationQueue = MockOutgoingMutationQueue()
        mockRequestRetryablePolicy = MockRequestRetryablePolicy()
        do {
            remoteSyncEngine = try RemoteSyncEngine(storageAdapter: storageAdapter,
                                                    dataStoreConfiguration: .default,
                                                    outgoingMutationQueue: mockOutgoingMutationQueue,
                                                    initialSyncOrchestratorFactory: MockAWSInitialSyncOrchestrator.factory,
                                                    reconciliationQueueFactory: MockAWSIncomingEventReconciliationQueue.factory,
                                                    requestRetryablePolicy: mockRequestRetryablePolicy)
        } catch {
            XCTFail("Failed to setup")
            return
        }
    }

    func testErrorOnNilStorageAdapter() throws {
        let failureOnStorageAdapter = expectation(description: "Expect receiveCompletion on storageAdapterFailure")

        storageAdapter = nil
        let remoteSyncEngineSink = remoteSyncEngine
            .publisher
            .sink(receiveCompletion: { _ in
                failureOnStorageAdapter.fulfill()
        }, receiveValue: { _ in
            XCTFail("We should not expect the sync engine not to continue")
        })

        remoteSyncEngine.start()

        wait(for: [failureOnStorageAdapter], timeout: defaultAsyncWaitTimeout)
    }

    func testFailureOnInitialSync() throws {
        let storageAdapterAvailable = expectation(description: "storageAdapterAvailable")
        let subscriptionsPaused = expectation(description: "subscriptionsPaused")
        let mutationsPaused = expectation(description: "mutationsPaused")
        let stateMutationsCleared = expectation(description: "stateMutationsCleared")
        let subscriptionsInitialized = expectation(description: "subscriptionsInitialized")
        let cleanedup = expectation(description: "cleanedup")
        let failureOnInitialSync = expectation(description: "failureOnInitialSync")

        var currCount = 1

        let advice = RequestRetryAdvice.init(shouldRetry: false)
        mockRequestRetryablePolicy.pushOnRetryRequestAdvice(response: advice)

        let remoteSyncEngineSink = remoteSyncEngine
            .publisher
            .sink(receiveCompletion: { _ in
                currCount = self.checkAndFulfill(currCount, 7, expectation: failureOnInitialSync)
            }, receiveValue: { event in
                switch event {
                case .storageAdapterAvailable:
                    currCount = self.checkAndFulfill(currCount, 1, expectation: storageAdapterAvailable)
                case .subscriptionsPaused:
                    currCount = self.checkAndFulfill(currCount, 2, expectation: subscriptionsPaused)
                case .mutationsPaused:
                    currCount = self.checkAndFulfill(currCount, 3, expectation: mutationsPaused)
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500)) {
                        MockAWSIncomingEventReconciliationQueue.mockSend(event: .initialized)
                    }
                case .clearedStateOutgoingMutations:
                    currCount = self.checkAndFulfill(currCount, 4, expectation: stateMutationsCleared)
                case .subscriptionsInitialized:
                    currCount = self.checkAndFulfill(currCount, 5, expectation: subscriptionsInitialized)
                case .performedInitialSync:
                    XCTFail("performedInitialQueries should not be successful")
                case .cleanedUp:
                    currCount = self.checkAndFulfill(currCount, 6, expectation: cleanedup)
                default:
                    XCTFail("Unexpected case gets hit")
                }
            })
        MockAWSInitialSyncOrchestrator.setResponseOnSync(result:
            .failure(DataStoreError.internalOperation("forceError", "none", nil)))

        remoteSyncEngine.start()

        wait(for: [storageAdapterAvailable,
                   subscriptionsPaused,
                   mutationsPaused,
                   stateMutationsCleared,
                   subscriptionsInitialized,
                   cleanedup,
                   failureOnInitialSync], timeout: defaultAsyncWaitTimeout)
    }

    func testRemoteSyncEngineHappyPath() throws {
        let storageAdapterAvailable = expectation(description: "storageAdapterAvailable")
        let subscriptionsPaused = expectation(description: "subscriptionsPaused")
        let mutationsPaused = expectation(description: "mutationsPaused")
        let stateMutationsCleared = expectation(description: "stateMutationsCleared")
        let subscriptionsInitialized = expectation(description: "subscriptionsInitialized")
        let performedInitialSync = expectation(description: "performedInitialSync")
        let subscriptionActivation = expectation(description: "failureOnSubscriptionActivation")
        let mutationQueueStarted = expectation(description: "mutationQueueStarted")
        let syncStarted = expectation(description: "sync started")

        var currCount = 1

        let remoteSyncEngineSink = remoteSyncEngine
            .publisher
            .sink(receiveCompletion: { _ in
                XCTFail("Completion should never happen")
            }, receiveValue: { event in
                switch event {
                case .storageAdapterAvailable:
                    currCount = self.checkAndFulfill(currCount, 1, expectation: storageAdapterAvailable)
                case .subscriptionsPaused:
                    currCount = self.checkAndFulfill(currCount, 2, expectation: subscriptionsPaused)
                case .mutationsPaused:
                    currCount = self.checkAndFulfill(currCount, 3, expectation: mutationsPaused)
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500)) {
                        MockAWSIncomingEventReconciliationQueue.mockSend(event: .initialized)
                    }
                case .clearedStateOutgoingMutations:
                    currCount = self.checkAndFulfill(currCount, 4, expectation: stateMutationsCleared)
                case .subscriptionsInitialized:
                    currCount = self.checkAndFulfill(currCount, 5, expectation: subscriptionsInitialized)
                case .performedInitialSync:
                    currCount = self.checkAndFulfill(currCount, 6, expectation: performedInitialSync)
                case .subscriptionsActivated:
                    currCount = self.checkAndFulfill(currCount, 7, expectation: subscriptionActivation)
                case .mutationQueueStarted:
                    currCount = self.checkAndFulfill(currCount, 8, expectation: mutationQueueStarted)
                case .syncStarted:
                    currCount = self.checkAndFulfill(currCount, 9, expectation: syncStarted)
                default:
                    XCTFail("unexpected call")
                }
            })

        remoteSyncEngine.start()

        wait(for: [storageAdapterAvailable,
                   subscriptionsPaused,
                   mutationsPaused,
                   stateMutationsCleared,
                   subscriptionsInitialized,
                   performedInitialSync,
                   subscriptionActivation,
                   mutationQueueStarted,
                   syncStarted], timeout: defaultAsyncWaitTimeout)
    }

    func testCatastrophicErrorEndsRemoteSyncEngine() throws {
        let storageAdapterAvailable = expectation(description: "storageAdapterAvailable")
        let subscriptionsPaused = expectation(description: "subscriptionsPaused")
        let mutationsPaused = expectation(description: "mutationsPaused")
        let stateMutationsCleared = expectation(description: "stateMutationsCleared")
        let subscriptionsInitialized = expectation(description: "subscriptionsInitialized")
        let performedInitialSync = expectation(description: "performedInitialSync")
        let subscriptionActivation = expectation(description: "failureOnSubscriptionActivation")
        let mutationQueueStarted = expectation(description: "mutationQueueStarted")
        let syncStarted = expectation(description: "syncStarted")
        let cleanedUp = expectation(description: "cleanedUp")
        let forceFailToNotRestartSyncEngine = expectation(description: "forceFailToNotRestartSyncEngine")

        var currCount = 1

        let advice = RequestRetryAdvice.init(shouldRetry: false)
        mockRequestRetryablePolicy.pushOnRetryRequestAdvice(response: advice)

        let remoteSyncEngineSink = remoteSyncEngine
            .publisher
            .sink(receiveCompletion: { _ in
                currCount = self.checkAndFulfill(currCount, 11, expectation: forceFailToNotRestartSyncEngine)
            }, receiveValue: { event in
                switch event {
                case .storageAdapterAvailable:
                    currCount = self.checkAndFulfill(currCount, 1, expectation: storageAdapterAvailable)
                case .subscriptionsPaused:
                    currCount = self.checkAndFulfill(currCount, 2, expectation: subscriptionsPaused)
                case .mutationsPaused:
                    currCount = self.checkAndFulfill(currCount, 3, expectation: mutationsPaused)
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500)) {
                        MockAWSIncomingEventReconciliationQueue.mockSend(event: .initialized)
                    }
                case .clearedStateOutgoingMutations:
                    currCount = self.checkAndFulfill(currCount, 4, expectation: stateMutationsCleared)
                case .subscriptionsInitialized:
                    currCount = self.checkAndFulfill(currCount, 5, expectation: subscriptionsInitialized)
                case .performedInitialSync:
                    currCount = self.checkAndFulfill(currCount, 6, expectation: performedInitialSync)
                case .subscriptionsActivated:
                    currCount = self.checkAndFulfill(currCount, 7, expectation: subscriptionActivation)
                case .mutationQueueStarted:
                    currCount = self.checkAndFulfill(currCount, 8, expectation: mutationQueueStarted)
                case .syncStarted:
                    currCount = self.checkAndFulfill(currCount, 9, expectation: syncStarted)
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500)) {
                        MockAWSIncomingEventReconciliationQueue.mockSendCompletion(completion: .failure(DataStoreError.unknown("", "", nil)))
                    }
                case .cleanedUp:
                    currCount = self.checkAndFulfill(currCount, 10, expectation: cleanedUp)
                default:
                    XCTFail("unexpected call")
                }
            })

        remoteSyncEngine.start()

        wait(for: [storageAdapterAvailable,
                   subscriptionsPaused,
                   mutationsPaused,
                   stateMutationsCleared,
                   subscriptionsInitialized,
                   performedInitialSync,
                   subscriptionActivation,
                   mutationQueueStarted,
                   syncStarted,
                   cleanedUp,
                   forceFailToNotRestartSyncEngine], timeout: defaultAsyncWaitTimeout)
    }

    func testStopEndsRemoteSyncEngine() throws {
        let storageAdapterAvailable = expectation(description: "storageAdapterAvailable")
        let subscriptionsPaused = expectation(description: "subscriptionsPaused")
        let mutationsPaused = expectation(description: "mutationsPaused")
        let stateMutationsCleared = expectation(description: "stateMutationsCleared")
        let subscriptionsInitialized = expectation(description: "subscriptionsInitialized")
        let performedInitialSync = expectation(description: "performedInitialSync")
        let subscriptionActivation = expectation(description: "failureOnSubscriptionActivation")
        let mutationQueueStarted = expectation(description: "mutationQueueStarted")
        let syncStarted = expectation(description: "syncStarted")
        let cleanedUpForTermination = expectation(description: "cleanedUpForTermination")
        let forceFailToNotRestartSyncEngine = expectation(description: "forceFailToNotRestartSyncEngine")
        let completionBlockCalled = expectation(description: "Completion block is called")

        var currCount = 1

        let advice = RequestRetryAdvice.init(shouldRetry: false)
        mockRequestRetryablePolicy.pushOnRetryRequestAdvice(response: advice)

        let remoteSyncEngineSink = remoteSyncEngine
            .publisher
            .sink(receiveCompletion: { _ in
                currCount = self.checkAndFulfill(currCount, 11, expectation: forceFailToNotRestartSyncEngine)
            }, receiveValue: { event in
                switch event {
                case .storageAdapterAvailable:
                    currCount = self.checkAndFulfill(currCount, 1, expectation: storageAdapterAvailable)
                case .subscriptionsPaused:
                    currCount = self.checkAndFulfill(currCount, 2, expectation: subscriptionsPaused)
                case .mutationsPaused:
                    currCount = self.checkAndFulfill(currCount, 3, expectation: mutationsPaused)
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500)) {
                        MockAWSIncomingEventReconciliationQueue.mockSend(event: .initialized)
                    }
                case .clearedStateOutgoingMutations:
                    currCount = self.checkAndFulfill(currCount, 4, expectation: stateMutationsCleared)
                case .subscriptionsInitialized:
                    currCount = self.checkAndFulfill(currCount, 5, expectation: subscriptionsInitialized)
                case .performedInitialSync:
                    currCount = self.checkAndFulfill(currCount, 6, expectation: performedInitialSync)
                case .subscriptionsActivated:
                    currCount = self.checkAndFulfill(currCount, 7, expectation: subscriptionActivation)
                case .mutationQueueStarted:
                    currCount = self.checkAndFulfill(currCount, 8, expectation: mutationQueueStarted)
                case .syncStarted:
                    currCount = self.checkAndFulfill(currCount, 9, expectation: syncStarted)
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500)) {
                        self.remoteSyncEngine.stop(completion: { result in
                            if case .success = result {
                                currCount = self.checkAndFulfill(currCount, 12, expectation: completionBlockCalled)
                            }
                        })
                    }
                case .cleanedUpForTermination:
                    currCount = self.checkAndFulfill(currCount, 10, expectation: cleanedUpForTermination)
                default:
                    XCTFail("unexpected call")
                }
            })

        remoteSyncEngine.start()

        wait(for: [storageAdapterAvailable,
                   subscriptionsPaused,
                   mutationsPaused,
                   stateMutationsCleared,
                   subscriptionsInitialized,
                   performedInitialSync,
                   subscriptionActivation,
                   mutationQueueStarted,
                   syncStarted,
                   cleanedUpForTermination,
                   completionBlockCalled,
                   forceFailToNotRestartSyncEngine], timeout: defaultAsyncWaitTimeout)
    }

    private func checkAndFulfill(_ currCount: Int, _ expectedCount: Int, expectation: XCTestExpectation) -> Int {
        if currCount == expectedCount {
            expectation.fulfill()
            return currCount + 1
        }
        return currCount
    }
}
