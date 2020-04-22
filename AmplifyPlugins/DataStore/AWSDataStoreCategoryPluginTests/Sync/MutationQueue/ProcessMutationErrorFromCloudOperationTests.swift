//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import XCTest
import Combine

@testable import Amplify
@testable import AmplifyTestCommon
@testable import AWSPluginsCore
@testable import AWSDataStoreCategoryPlugin

// swiftlint:disable type_body_length
@available(iOS 13.0, *)
class ProcessMutationErrorFromCloudOperationTests: XCTestCase {
    let defaultAsyncWaitTimeout = 10.0
    var mockAPIPlugin: MockAPICategoryPlugin!
    var storageAdapter: StorageEngineAdapter!

    override func setUp() {
        tryOrFail {
            try setUpWithAPI()
        }
        storageAdapter = MockSQLiteStorageEngineAdapter()

        ModelRegistry.register(modelType: Post.self)
        ModelRegistry.register(modelType: Comment.self)
    }

    func testProcessMutationErrorFromCloudOperationSuccessForConditionalCheck() throws {
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let expectHubEvent = expectation(description: "Hub is notified")

        let hubListener = Amplify.Hub.listen(to: .dataStore) { payload in
            if payload.eventName == "DataStore.conditionalSaveFailed" {
                expectHubEvent.fulfill()
            }
        }

        let completion: (Result<Void, Error>) -> Void = { result in
            expectCompletion.fulfill()
        }
        let post1 = Post(title: "post1", content: "content1", createdAt: Date())
        let mutationEvent = try MutationEvent(model: post1, mutationType: .create)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conditional request failed",
            errorType: AppSyncErrorType.conditionalCheck.rawValue)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])

        let operation = ProcessMutationErrorFromCloudOperation(configuration: .default,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)

        let queue = OperationQueue()
        queue.addOperation(operation)

        wait(for: [expectHubEvent, expectCompletion], timeout: defaultAsyncWaitTimeout)
        Amplify.Hub.removeListener(hubListener)

    }


    /// - Given: Conflict Unhandled error
    /// - When:
    ///    - Error does not contain the remote model
    /// - Then:
    ///    - Unexpected scenario, there should never be an conflict unhandled error without error.data
    func testConflictUnhandledReturnsErrorForMissingRemoteModel() throws {
        let localPost = Post(title: "localTitle", content: "localContent", createdAt: Date())
        let mutationEvent = try MutationEvent(model: localPost, mutationType: .create)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conflict unhandled",
            errorType: AppSyncErrorType.conflictUnhandled.rawValue)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let completion: (Result<Void, Error>) -> Void = { result in
            guard case let .failure(error) = result,
                let dataStoreError = error as? DataStoreError,
                case .unknown = dataStoreError else {
                XCTFail("Should have failed with DataStoreError.unknown")
                return
            }

            XCTAssertEqual(dataStoreError.errorDescription, "Missing remote model from the response from AppSync.")
            expectCompletion.fulfill()
        }
        let operation = ProcessMutationErrorFromCloudOperation(configuration: .default,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)
        let queue = OperationQueue()
        queue.addOperation(operation)
        wait(for: [expectCompletion], timeout: defaultAsyncWaitTimeout)
    }

    /// - Given: Conflict Unhandled error
    /// - When:
    ///    - MutationType is `create`
    /// - Then:
    ///    - Unexpected scenario, there should never get a conflict for create mutations
    func testConflictUnhandledReturnsErrorForCreateMutation() throws {
        let localPost = Post(title: "localTitle", content: "localContent", createdAt: Date())
        let remotePost = Post(title: "remoteTitle", content: "remoteContent", createdAt: Date())
        let mutationEvent = try MutationEvent(model: localPost, mutationType: .create)
        let remoteMetadata = MutationSyncMetadata(id: remotePost.id, deleted: false, lastChangedAt: 0, version: 1)
        let remoteModel = MutationSync(model: try remotePost.eraseToAnyModel(), syncMetadata: remoteMetadata)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conflict unhandled", errorType: AppSyncErrorType.conflictUnhandled.rawValue, data: remoteModel)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let completion: (Result<Void, Error>) -> Void = { result in
            guard case let .failure(error) = result,
                let dataStoreError = error as? DataStoreError,
                case .unknown = dataStoreError else {
                XCTFail("Should have failed with DataStoreError.unknown")
                return
            }

            XCTAssertEqual(dataStoreError.errorDescription, "Should never get conflict unhandled for create mutation")
            expectCompletion.fulfill()
        }
        let operation = ProcessMutationErrorFromCloudOperation(configuration: .default,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)
        let queue = OperationQueue()
        queue.addOperation(operation)
        wait(for: [expectCompletion], timeout: defaultAsyncWaitTimeout)
    }

    /// - Given: Conflict Unhandled error
    /// - When:
    ///    - MutationType is `delete`, remote model is deleted.
    /// - Then:
    ///    - No-op, operation finishes successfully
    func testConflictUnhandledForDeleteMutationAndDeletedRemoteModel() throws {
        let localPost = Post(title: "localTitle", content: "localContent", createdAt: Date())
        let remotePost = Post(title: "remoteTitle", content: "remoteContent", createdAt: Date())
        let mutationEvent = MutationEvent(modelId: localPost.id, modelName: localPost.modelName, json: "{}",
                                          mutationType: .delete)
        let remoteMetadata = MutationSyncMetadata(id: remotePost.id, deleted: true, lastChangedAt: 0, version: 1)
        let remoteModel = MutationSync(model: try remotePost.eraseToAnyModel(), syncMetadata: remoteMetadata)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conflict unhandled", errorType: AppSyncErrorType.conflictUnhandled.rawValue, data: remoteModel)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let completion: (Result<Void, Error>) -> Void = { result in
            guard case .success = result else {
                XCTFail("Should have been successful")
                return
            }
            expectCompletion.fulfill()
        }
        let operation = ProcessMutationErrorFromCloudOperation(configuration: .default,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)
        let queue = OperationQueue()
        queue.addOperation(operation)
        wait(for: [expectCompletion], timeout: defaultAsyncWaitTimeout)
    }

    /// - Given: Conflict Unhandled error
    /// - When:
    ///    - MutationType is `delete`, remote model is an update
    /// - Then:
    ///    - Local Store is reconciled to remote model
    func testConflictUnhandledForDeleteMutationAndUpdatedRemoteModel() throws {
        let localPost = Post(title: "localTitle", content: "localContent", createdAt: Date())
        let remotePost = Post(title: "remoteTitle", content: "remoteContent", createdAt: Date())
        let mutationEvent = MutationEvent(modelId: localPost.id, modelName: localPost.modelName, json: "{}",
                                          mutationType: .delete)
        let remoteMetadata = MutationSyncMetadata(id: remotePost.id, deleted: false, lastChangedAt: 0, version: 2)
        let remoteModel = MutationSync(model: try remotePost.eraseToAnyModel(), syncMetadata: remoteMetadata)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conflict unhandled", errorType: AppSyncErrorType.conflictUnhandled.rawValue, data: remoteModel)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let completion: (Result<Void, Error>) -> Void = { result in
            guard case .success = result else {
                XCTFail("Should have been successful")
                return
            }
            expectCompletion.fulfill()
        }

        let modelSavedEvent = expectation(description: "model saved event")
        modelSavedEvent.expectedFulfillmentCount = 2
        let storageAdapter = MockSQLiteStorageEngineAdapter()
        storageAdapter.responders[.saveUntypedModel] = SaveUntypedModelResponder { model, completion in
            guard let savedPost = model as? Post else {
                XCTFail("Couldn't get Posts from local and remote data")
                return
            }
            XCTAssertEqual(savedPost.title, remotePost.title)
            modelSavedEvent.fulfill()
            completion(.success(model))
        }

        storageAdapter.responders[.saveModelCompletion] =
            SaveModelCompletionResponder<MutationSyncMetadata> { metadata, completion in
            XCTAssertEqual(metadata.deleted, false)
            XCTAssertEqual(metadata.version, remoteMetadata.version)
            modelSavedEvent.fulfill()
            completion(.success(metadata))
        }

        let expectHubEvent = expectation(description: "Hub is notified")
        let hubListener = Amplify.Hub.listen(to: .dataStore) { payload in
            if payload.eventName == "DataStore.syncReceived" {
                expectHubEvent.fulfill()
            }
        }
        let operation = ProcessMutationErrorFromCloudOperation(configuration: .default,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)

        let queue = OperationQueue()
        queue.addOperation(operation)

        wait(for: [expectHubEvent, modelSavedEvent, expectCompletion], timeout: defaultAsyncWaitTimeout)
        Amplify.Hub.removeListener(hubListener)
    }

    /// - Given: Conflict Unhandled error
    /// - When:
    ///    - MutationType is `update`, remote model is deleted
    /// - Then:
    ///    - Local model is deleted
    func testConflictUnhandledForUpdateMutationAndDeletedRemoteModel() throws {
        let localPost = Post(title: "localTitle", content: "localContent", createdAt: Date())
        let remotePost = Post(title: "remoteTitle", content: "remoteContent", createdAt: Date())
        let mutationEvent = try MutationEvent(model: localPost, mutationType: .update)
        let remoteMetadata = MutationSyncMetadata(id: remotePost.id, deleted: true, lastChangedAt: 0, version: 2)
        let remoteModel = MutationSync(model: try remotePost.eraseToAnyModel(), syncMetadata: remoteMetadata)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conflict unhandled", errorType: AppSyncErrorType.conflictUnhandled.rawValue, data: remoteModel)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let completion: (Result<Void, Error>) -> Void = { result in
            guard case .success = result else {
                XCTFail("Should have been successful")
                return
            }
            expectCompletion.fulfill()
        }

        let modelDeletedEvent = expectation(description: "model deleted event")
        let metadataSavedEvent = expectation(description: "metadata saved event")
        let storageAdapter = MockSQLiteStorageEngineAdapter()
        storageAdapter.shouldReturnErrorOnDeleteMutation = false
        storageAdapter.responders[.deleteUntypedModel] = DeleteUntypedModelCompletionResponder { _ in
            modelDeletedEvent.fulfill()
        }
        storageAdapter.responders[.saveModelCompletion] =
            SaveModelCompletionResponder<MutationSyncMetadata> { metadata, completion in
            XCTAssertEqual(metadata.deleted, true)
            XCTAssertEqual(metadata.version, remoteMetadata.version)
            metadataSavedEvent.fulfill()
            completion(.success(metadata))
        }

        let expectHubEvent = expectation(description: "Hub is notified")
        let hubListener = Amplify.Hub.listen(to: .dataStore) { payload in
            if payload.eventName == "DataStore.syncReceived" {
                expectHubEvent.fulfill()
            }
        }
        let operation = ProcessMutationErrorFromCloudOperation(configuration: .default,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)

        let queue = OperationQueue()
        queue.addOperation(operation)

        wait(for: [modelDeletedEvent, metadataSavedEvent, expectHubEvent, expectCompletion],
             timeout: defaultAsyncWaitTimeout)
        Amplify.Hub.removeListener(hubListener)
    }

    /// - Given: Conflict Unhandled error
    /// - When:
    ///    - MutationType is `update`, remote model is an update, conflict handler returns `.applyRemote`
    /// - Then:
    ///    - Local model is updated with remote model data
    func testConflictUnhandledConflictHandlerReturnsApplyRemote() throws {
        let localPost = Post(title: "localTitle", content: "localContent", createdAt: Date())
        let remotePost = Post(title: "remoteTitle", content: "remoteContent", createdAt: Date())
        let mutationEvent = try MutationEvent(model: localPost, mutationType: .update)
        let remoteMetadata = MutationSyncMetadata(id: remotePost.id, deleted: false, lastChangedAt: 0, version: 2)
        let remoteModel = MutationSync(model: try remotePost.eraseToAnyModel(), syncMetadata: remoteMetadata)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conflict unhandled", errorType: AppSyncErrorType.conflictUnhandled.rawValue, data: remoteModel)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let completion: (Result<Void, Error>) -> Void = { result in
            guard case .success = result else {
                XCTFail("Should have been successful")
                return
            }
            expectCompletion.fulfill()
        }

        let storageAdapter = MockSQLiteStorageEngineAdapter()
        let modelSavedEvent = expectation(description: "model saved event")
        modelSavedEvent.expectedFulfillmentCount = 2
        storageAdapter.responders[.saveUntypedModel] = SaveUntypedModelResponder { model, completion in
            guard let savedPost = model as? Post else {
                XCTFail("Couldn't get Posts from local and remote data")
                return
            }
            XCTAssertEqual(savedPost.title, remotePost.title)
            modelSavedEvent.fulfill()
            completion(.success(model))
        }
        storageAdapter.responders[.saveModelCompletion] =
            SaveModelCompletionResponder<MutationSyncMetadata> { metadata, completion in
            XCTAssertEqual(metadata.deleted, false)
            XCTAssertEqual(metadata.version, remoteMetadata.version)
            modelSavedEvent.fulfill()
            completion(.success(metadata))
        }

        let expectHubEvent = expectation(description: "Hub is notified")
        let hubListener = Amplify.Hub.listen(to: .dataStore) { payload in
            if payload.eventName == "DataStore.syncReceived" {
                expectHubEvent.fulfill()
            }
        }
        let expectConflicthandlerCalled = expectation(description: "Expect conflict handler called")
        let configuration = DataStoreConfiguration.custom(conflictHandler: { data, resolve  in
            guard let localPost = data.local as? Post,
                let remotePost = data.remote as? Post else {
                XCTFail("Couldn't get Posts from local and remote data")
                return
            }

            XCTAssertEqual(localPost.title, "localTitle")
            XCTAssertEqual(remotePost.title, "remoteTitle")
            expectConflicthandlerCalled.fulfill()
            resolve(.applyRemote)
        })
        let operation = ProcessMutationErrorFromCloudOperation(configuration: configuration,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)

        let queue = OperationQueue()
        queue.addOperation(operation)

        wait(for: [expectConflicthandlerCalled, modelSavedEvent, expectHubEvent, expectCompletion],
             timeout: defaultAsyncWaitTimeout)
        Amplify.Hub.removeListener(hubListener)
    }

    /// - Given: Conflict Unhandled error
    /// - When:
    ///    - MutationType is `update`, remote model is an update, conflict handler returns `.retryLocal`
    /// - Then:
    ///    - API is called with the local model
    func testConflictUnhandledConflictHandlerReturnsRetryLocal() throws {
        let localPost = Post(title: "localTitle", content: "localContent", createdAt: Date())
        let remotePost = Post(title: "remoteTitle", content: "remoteContent", createdAt: Date())
        let mutationEvent = try MutationEvent(model: localPost, mutationType: .update)
        let remoteMetadata = MutationSyncMetadata(id: remotePost.id, deleted: false, lastChangedAt: 0, version: 2)
        let remoteModel = MutationSync(model: try remotePost.eraseToAnyModel(), syncMetadata: remoteMetadata)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conflict unhandled", errorType: AppSyncErrorType.conflictUnhandled.rawValue, data: remoteModel)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let completion: (Result<Void, Error>) -> Void = { result in
            guard case .success = result else {
                XCTFail("Should have been successful")
                return
            }
            expectCompletion.fulfill()
        }

        var eventListenerOptional: GraphQLOperation<MutationSync<AnyModel>>.EventListener?
        let apiMutateCalled = expectation(description: "API was called")
        mockAPIPlugin.responders[.mutateRequestListener] =
            MutateRequestListenerResponder<MutationSync<AnyModel>> { request, eventListener in
                guard let variables = request.variables, let input = variables["input"] as? [String: Any] else {
                    XCTFail("The document variables property doesn't contain a valid input")
                    return nil
                }
                XCTAssert(input["title"] as? String == localPost.title)
                eventListenerOptional = eventListener
                apiMutateCalled.fulfill()
                return nil
        }

        let expectConflicthandlerCalled = expectation(description: "Expect conflict handler called")
        let configuration = DataStoreConfiguration.custom(conflictHandler: { data, resolve  in
            guard let localPost = data.local as? Post,
                let remotePost = data.remote as? Post else {
                XCTFail("Couldn't get Posts from local and remote data")
                return
            }

            XCTAssertEqual(localPost.title, "localTitle")
            XCTAssertEqual(remotePost.title, "remoteTitle")
            expectConflicthandlerCalled.fulfill()
            resolve(.retryLocal)
        })
        let operation = ProcessMutationErrorFromCloudOperation(configuration: configuration,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)

        let queue = OperationQueue()
        queue.addOperation(operation)

        wait(for: [expectConflicthandlerCalled, apiMutateCalled], timeout: defaultAsyncWaitTimeout)
        guard let eventListener = eventListenerOptional else {
            XCTFail("Listener was not called through MockAPICategoryPlugin")
            return
        }
        let updatedMetadata = MutationSyncMetadata(id: remotePost.id, deleted: false, lastChangedAt: 0, version: 3)
        let local = MutationSync(model: try localPost.eraseToAnyModel(), syncMetadata: updatedMetadata)
        eventListener(.completed(.success(local)))
        wait(for: [expectCompletion], timeout: defaultAsyncWaitTimeout)
    }

    /// - Given: Conflict Unhandled error
    /// - When:
    ///    - MutationType is `update`, remote model is an update, conflict handler returns `.retry(Model)`
    /// - Then:
    ///    - API is called with the model from the conflict handler result
    func testConflictUnhandledConflicthandlerReturnsRetryModel() throws {
        let localPost = Post(title: "localTitle", content: "localContent", createdAt: Date())
        let remotePost = Post(title: "remoteTitle", content: "remoteContent", createdAt: Date())
        let mutationEvent = try MutationEvent(model: localPost, mutationType: .update)
        let remoteMetadata = MutationSyncMetadata(id: remotePost.id, deleted: false, lastChangedAt: 0, version: 2)
        let remoteModel = MutationSync(model: try remotePost.eraseToAnyModel(), syncMetadata: remoteMetadata)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conflict unhandled", errorType: AppSyncErrorType.conflictUnhandled.rawValue, data: remoteModel)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let completion: (Result<Void, Error>) -> Void = { result in
            guard case .success = result else {
                XCTFail("Should have been successful")
                return
            }
            expectCompletion.fulfill()
        }

        let retryModel = Post(title: "retryModel", content: "retryContent", createdAt: Date())
        var eventListenerOptional: GraphQLOperation<MutationSync<AnyModel>>.EventListener?
        let apiMutateCalled = expectation(description: "API was called")
        mockAPIPlugin.responders[.mutateRequestListener] =
            MutateRequestListenerResponder<MutationSync<AnyModel>> { request, eventListener in
                guard let variables = request.variables, let input = variables["input"] as? [String: Any] else {
                    XCTFail("The document variables property doesn't contain a valid input")
                    return nil
                }
                XCTAssert(input["title"] as? String == retryModel.title)
                eventListenerOptional = eventListener
                apiMutateCalled.fulfill()
                return nil
        }

        let expectConflicthandlerCalled = expectation(description: "Expect conflict handler called")
        let configuration = DataStoreConfiguration.custom(conflictHandler: { data, resolve  in
            guard let localPost = data.local as? Post,
                let remotePost = data.remote as? Post else {
                XCTFail("Couldn't get Posts from local and remote data")
                return
            }

            XCTAssertEqual(localPost.title, "localTitle")
            XCTAssertEqual(remotePost.title, "remoteTitle")
            expectConflicthandlerCalled.fulfill()
            resolve(.retry(retryModel))
        })
        let operation = ProcessMutationErrorFromCloudOperation(configuration: configuration,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)

        let queue = OperationQueue()
        queue.addOperation(operation)

        wait(for: [expectConflicthandlerCalled, apiMutateCalled], timeout: defaultAsyncWaitTimeout)
        guard let eventListener = eventListenerOptional else {
            XCTFail("Listener was not called through MockAPICategoryPlugin")
            return
        }
        let updatedMetadata = MutationSyncMetadata(id: remotePost.id, deleted: false, lastChangedAt: 0, version: 3)
        let local = MutationSync(model: try localPost.eraseToAnyModel(), syncMetadata: updatedMetadata)
        eventListener(.completed(.success(local)))
        wait(for: [expectCompletion], timeout: defaultAsyncWaitTimeout)
    }

    /// - Given: Conflict Unhandled error
    /// - When:
    ///    - MutationType is `update`, remote model is an update, conflict handler returns `.retryLocal`
    ///    - API is called with local model and response contains error
    /// - Then:
    ///    - `DataStoreErrorHandler` is called
    func testConflictUnhandledSyncToCloudReturnsError() throws {
        let localPost = Post(title: "localTitle", content: "localContent", createdAt: Date())
        let remotePost = Post(title: "remoteTitle", content: "remoteContent", createdAt: Date())
        let mutationEvent = try MutationEvent(model: localPost, mutationType: .update)
        let remoteMetadata = MutationSyncMetadata(id: remotePost.id, deleted: false, lastChangedAt: 0, version: 2)
        let remoteModel = MutationSync(model: try remotePost.eraseToAnyModel(), syncMetadata: remoteMetadata)
        let graphQLError = AppSyncGraphQLError<MutationSync<AnyModel>>(
            message: "conflict unhandled", errorType: AppSyncErrorType.conflictUnhandled.rawValue, data: remoteModel)
        let graphQLResponseError = GraphQLResponseError<MutationSync<AnyModel>>.error([graphQLError])
        let expectCompletion = expectation(description: "Expect to complete error processing")
        let completion: (Result<Void, Error>) -> Void = { result in
            guard case .success = result else {
                XCTFail("Should have been successful")
                return
            }
            expectCompletion.fulfill()
        }

        var eventListenerOptional: GraphQLOperation<MutationSync<AnyModel>>.EventListener?
        let apiMutateCalled = expectation(description: "API was called")
        mockAPIPlugin.responders[.mutateRequestListener] =
            MutateRequestListenerResponder<MutationSync<AnyModel>> { request, eventListener in
                guard let variables = request.variables, let input = variables["input"] as? [String: Any] else {
                    XCTFail("The document variables property doesn't contain a valid input")
                    return nil
                }
                XCTAssert(input["title"] as? String == localPost.title)
                eventListenerOptional = eventListener
                apiMutateCalled.fulfill()
                return nil
        }

        let expectConflicthandlerCalled = expectation(description: "Expect conflict handler called")
        let expectErrorHandlerCalled = expectation(description: "Expect error handler called")
        let configuration = DataStoreConfiguration.custom(errorHandler: { error in
            expectErrorHandlerCalled.fulfill()
        }, conflictHandler: { data, resolve in
            guard let localPost = data.local as? Post,
                let remotePost = data.remote as? Post else {
                XCTFail("Couldn't get Posts from local and remote data")
                return
            }

            XCTAssertEqual(localPost.title, "localTitle")
            XCTAssertEqual(remotePost.title, "remoteTitle")
            expectConflicthandlerCalled.fulfill()
            resolve(.retryLocal)
        })
        let operation = ProcessMutationErrorFromCloudOperation(configuration: configuration,
                                                               mutationEvent: mutationEvent,
                                                               api: mockAPIPlugin,
                                                               storageAdapter: storageAdapter,
                                                               error: graphQLResponseError,
                                                               completion: completion)

        let queue = OperationQueue()
        queue.addOperation(operation)

        wait(for: [expectConflicthandlerCalled, apiMutateCalled], timeout: defaultAsyncWaitTimeout)
        guard let eventListener = eventListenerOptional else {
            XCTFail("Listener was not called through MockAPICategoryPlugin")
            return
        }

        let error = AppSyncGraphQLError<MutationSync<AnyModel>>(message: "some other error", errorType: "errorType")
        eventListener(.completed(.failure(.error([error]))))

        wait(for: [expectErrorHandlerCalled, expectCompletion], timeout: defaultAsyncWaitTimeout)
    }
}

extension ProcessMutationErrorFromCloudOperationTests {
    private func setUpCore() throws -> AmplifyConfiguration {
        Amplify.reset()

        let storageEngine = MockStorageEngineBehavior()
        let dataStorePublisher = DataStorePublisher()
        let dataStorePlugin = AWSDataStorePlugin(schema: TestDataStoreSchema(),
                                                 storageEngine: storageEngine,
                                                 dataStorePublisher: dataStorePublisher)
        try Amplify.add(plugin: dataStorePlugin)
        let dataStoreConfig = DataStoreCategoryConfiguration(plugins: [
            "awsDataStorePlugin": true
        ])

        let amplifyConfig = AmplifyConfiguration(dataStore: dataStoreConfig)

        return amplifyConfig
    }

    private func setUpAPICategory(config: AmplifyConfiguration) throws -> AmplifyConfiguration {
        mockAPIPlugin = MockAPICategoryPlugin()
        try Amplify.add(plugin: mockAPIPlugin)

        let apiConfig = APICategoryConfiguration(plugins: [
            "MockAPICategoryPlugin": true
        ])
        let amplifyConfig = AmplifyConfiguration(api: apiConfig, dataStore: config.dataStore)
        return amplifyConfig
    }

    private func setUpWithAPI() throws {
        let configWithoutAPI = try setUpCore()
        let configWithAPI = try setUpAPICategory(config: configWithoutAPI)
        try Amplify.configure(configWithAPI)
    }
}
