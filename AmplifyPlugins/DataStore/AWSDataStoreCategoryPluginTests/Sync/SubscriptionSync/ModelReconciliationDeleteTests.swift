//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Combine
import XCTest

@testable import Amplify
@testable import AmplifyTestCommon
@testable import AWSPluginsCore
@testable import AWSDataStoreCategoryPlugin

/// Tests system behavior at a higher level than the reconciler tests--ensures data is appropriately applied and deleted
class ModelReconciliationDeleteTests: SyncEngineTestBase {

    /// - Given:
    ///   - A sync-enabled DataStore
    ///   - The local datastore has received a delete mutation
    /// - When:
    ///    - The sync engine receives an update mutation
    /// - Then:
    ///    - The update is not applied
    func testUpdateAfterDelete() throws {
        let expectationListener = expectation(description: "listener")
        tryOrFail {
            try setUpStorageAdapter(preCreating: [MockSynced.self])
        }

        let model = MockSynced(id: "id-1")
        let localSyncMetadata = MutationSyncMetadata(id: model.id,
                                                        deleted: true,
                                                        lastChangedAt: Date().unixSeconds,
                                                        version: 2)
        let localMetadataSaved = expectation(description: "Local metadata saved")
        storageAdapter.save(localSyncMetadata) { _ in localMetadataSaved.fulfill() }
        wait(for: [localMetadataSaved], timeout: 1.0)

        var listenerFromRequest: GraphQLSubscriptionOperation<MutationSync<AnyModel>>.EventListener?

        let responder = SubscribeRequestListenerResponder<MutationSync<AnyModel>> { request, listener in
            if request.document.contains("onUpdateMockSynced") {
                listenerFromRequest = listener
                expectationListener.fulfill()
            }
            return nil
        }

        apiPlugin.responders[.subscribeRequestListener] = responder

        tryOrFail {
            try setUpDataStore(schema: MockModelSchemaProvider())
            mockRemoteSyncEngineFor_testUpdateAfterDelete()
            try startAmplifyAndWaitForSync()
        }
        wait(for: [expectationListener], timeout: 2.0)

        guard let listener = listenerFromRequest else {
            XCTFail("Incoming responder didn't set up listener")
            return
        }

        let anyModel = try model.eraseToAnyModel()
        let remoteSyncMetadata = MutationSyncMetadata(id: model.id,
                                                      deleted: false,
                                                      lastChangedAt: Date().unixSeconds,
                                                      version: 1)
        let remoteMutationSync = MutationSync(model: anyModel, syncMetadata: remoteSyncMetadata)
        listener(.inProcess(.data(.success(remoteMutationSync))))

        // Because we expect this event to be dropped, there won't be a Hub notification or callback to listen to, so
        // we have to brute-force this wait
        Thread.sleep(forTimeInterval: 1.0)

        let finalLocalMetadata = try storageAdapter.queryMutationSyncMetadata(for: model.id)
        XCTAssertEqual(finalLocalMetadata?.version, 2)
        XCTAssertEqual(finalLocalMetadata?.deleted, true)

        storageAdapter.query(untypedModel: MockSynced.self) { results in
            switch results {
            case .failure(let error):
                XCTAssertNil(error)
            case .success(let results):
                XCTAssertEqual(results.count, 0)
            }
        }
    }

    func mockRemoteSyncEngineFor_testUpdateAfterDelete() {
        remoteSyncEngineSink = syncEngine
            .publisher
            .sink(receiveCompletion: {_ in },
                  receiveValue: { event in
                    switch event {
                    case .mutationsPaused:
                        //Assume AWSIncomingEventReconciliationQueue succeeds in establishing connections
                        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500)) {
                            let request = GraphQLRequest<MutationSync<AnyModel>>.subscription(to: MockSynced.self,
                                                                                              subscriptionType: .onUpdate)
                            let onUpdateListener: GraphQLSubscriptionOperation<MutationSync<AnyModel>>.EventListener = { event in
                                print("emptyListener")
                            }
                            let operation = self.apiPlugin.subscribe(request: request, listener: onUpdateListener)
                            MockAWSIncomingEventReconciliationQueue.mockSend(event: .initialized)
                        }
                    default:
                        break
                    }
            })
    }

    /// - Given:
    ///   - A sync-enabled DataStore
    ///   - The local datastore has no local model
    /// - When:
    ///    - The sync engine receives a delete mutation
    /// - Then:
    ///    - The delete metadata record is written but no model record is written
    func testDeleteWithNoLocalModel() throws {
        let expectationListener = expectation(description: "listener")

        tryOrFail {
            try setUpStorageAdapter()
        }

        var listenerFromRequest: GraphQLSubscriptionOperation<MutationSync<AnyModel>>.EventListener?

        let responder = SubscribeRequestListenerResponder<MutationSync<AnyModel>> { request, listener in
            if request.document.contains("onUpdateMockSynced") {
                listenerFromRequest = listener
                expectationListener.fulfill()
            }

            return nil
        }

        apiPlugin.responders[.subscribeRequestListener] = responder

        tryOrFail {
            try setUpDataStore(schema: MockModelSchemaProvider())
            mockRemoteSyncEngineFor_testDeleteWithNoLocalModel()
            try startAmplifyAndWaitForSync()
        }
        wait(for: [expectationListener], timeout: 1.0)

        guard let listener = listenerFromRequest else {
            XCTFail("Incoming responder didn't set up listener")
            return
        }

        let syncReceivedNotification = expectation(description: "Received 'syncReceived' update from Hub")
        let syncReceivedToken = Amplify.Hub.listen(to: .dataStore,
                                                   eventName: HubPayload.EventName.DataStore.syncReceived) { _ in
            syncReceivedNotification.fulfill()
        }
        guard try HubListenerTestUtilities.waitForListener(with: syncReceivedToken, timeout: 5.0) else {
            XCTFail("Sync listener never registered")
            return
        }

        let model = MockSynced(id: "id-1")
        let anyModel = try model.eraseToAnyModel()
        let remoteSyncMetadata = MutationSyncMetadata(id: model.id,
                                                      deleted: true,
                                                      lastChangedAt: Date().unixSeconds,
                                                      version: 2)
        let remoteMutationSync = MutationSync(model: anyModel, syncMetadata: remoteSyncMetadata)
        listener(.inProcess(.data(.success(remoteMutationSync))))

        wait(for: [syncReceivedNotification], timeout: 1.0)

        let finalLocalMetadata = try storageAdapter.queryMutationSyncMetadata(for: model.id)
        XCTAssertEqual(finalLocalMetadata?.version, 2)
        XCTAssertEqual(finalLocalMetadata?.deleted, true)

        storageAdapter.query(untypedModel: MockSynced.self) { results in
            switch results {
            case .failure(let error):
                XCTAssertNil(error)
            case .success(let results):
                XCTAssertEqual(results.count, 0)
            }
        }

        Amplify.Hub.removeListener(syncReceivedToken)
    }

    func mockRemoteSyncEngineFor_testDeleteWithNoLocalModel() {
        remoteSyncEngineSink = syncEngine
            .publisher
            .sink(receiveCompletion: {_ in },
                  receiveValue: { event in
                    switch event {
                    case .mutationsPaused:
                        //Assume AWSIncomingEventReconciliationQueue succeeds in establishing connections
                        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500)) {
                            let request = GraphQLRequest<MutationSync<AnyModel>>.subscription(to: MockSynced.self,
                                                                                              subscriptionType: .onUpdate)
                            let onUpdateListener: GraphQLSubscriptionOperation<MutationSync<AnyModel>>.EventListener = { event in
                                switch event {
                                case .inProcess(.data(.success(let mutationEvent))):
                                    self.storageAdapter.save(mutationEvent.syncMetadata) { result in
                                        switch result {
                                        case .success(let syncMetaData):
                                            let payload = HubPayload(eventName: HubPayload.EventName.DataStore.syncReceived,
                                                                     data: syncMetaData)
                                            Amplify.Hub.dispatch(to: .dataStore, payload: payload)
                                        default:
                                            break
                                        }

                                    }
                                default:
                                    break
                                }
                            }
                            let operation = self.apiPlugin.subscribe(request: request, listener: onUpdateListener)
                            MockAWSIncomingEventReconciliationQueue.mockSend(event: .initialized)
                        }
                    default:
                        break
                    }
            })
    }
}
