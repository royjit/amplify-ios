//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Amplify
import Combine
import Foundation
import AWSPluginsCore

/// Checks the GraphQL error response for specific error scenarios related to data synchronziation to the local store.
/// 1. When there is a "conditional request failed" error, then emit to the Hub a 'conditionalSaveFailed' event.
@available(iOS 13.0, *)
class ProcessMutationErrorFromCloudOperation: AsynchronousOperation {

    private let configuration: DataStoreConfiguration
    private let mutationEvent: MutationEvent
    private let error: GraphQLResponseError<MutationSync<AnyModel>>
    private let completion: (Result<Void, Error>) -> Void
    private let mutationEventPublisher: PassthroughSubject<MutationEvent, DataStoreError>

    private var mutationOperation: GraphQLOperation<MutationSync<AnyModel>>?

    private weak var storageAdapter: StorageEngineAdapter?
    private weak var api: APICategoryGraphQLBehavior?

    init(configuration: DataStoreConfiguration,
         mutationEvent: MutationEvent,
         api: APICategoryGraphQLBehavior,
         storageAdapter: StorageEngineAdapter,
         error: GraphQLResponseError<MutationSync<AnyModel>>,
         completion: @escaping (Result<Void, Error>) -> Void) {
        self.configuration = configuration
        self.mutationEvent = mutationEvent
        self.api = api
        self.storageAdapter = storageAdapter
        self.error = error
        self.completion = completion
        self.mutationEventPublisher = PassthroughSubject<MutationEvent, DataStoreError>()
        super.init()
    }

    override func main() {
        log.verbose(#function)

        guard !isCancelled else {
            mutationOperation?.cancel()
            let apiError = DataStoreError.unknown("Operation cancelled", "")
            finish(result: .failure(apiError))
            return
        }

        guard case let .error(graphQLErrors) = error else {
            finish(result: .success(()))
            return
        }

        guard graphQLErrors.count == 1 else {
            finish(result: .success(()))
            return
        }

        guard let graphQLError = graphQLErrors.first else {
            finish(result: .success(()))
            return
        }

        if let appSyncError = graphQLError as? AppSyncGraphQLError<MutationSync<AnyModel>>,
            let errorType = appSyncError.appSyncErrorType {

            if errorType == .conditionalCheck {
                let payload = HubPayload(eventName: HubPayload.EventName.DataStore.conditionalSaveFailed,
                                         data: mutationEvent)
                Amplify.Hub.dispatch(to: .dataStore, payload: payload)
                finish(result: .success(()))
            } else if errorType == .conflictUnhandled {
                processConflictUnhandled(appSyncError)
            }
        }
    }

    private func processConflictUnhandled(_ appSyncError: AppSyncGraphQLError<MutationSync<AnyModel>>) {
        guard let remote = appSyncError.data else {
            let error = DataStoreError.unknown("Missing remote model from the response from AppSync.",
                                               "This indicates something unexpected was returned from the service")
            finish(result: .failure(error))
            return
        }

        guard let mutationType = GraphQLMutationType(rawValue: mutationEvent.mutationType) else {
            let dataStoreError = DataStoreError.decodingError(
                "Invalid mutation type",
                """
                The incoming mutation event had a mutation type of \(mutationEvent.mutationType), which does not
                match any known GraphQL mutation type. Ensure you only send valid mutation types:
                \(GraphQLMutationType.allCases)
                """
            )
            log.error(error: dataStoreError)
            finish(result: .failure(dataStoreError))
            return
        }

        switch mutationType {
        case .create:
            let error = DataStoreError.unknown("Should never get conflict unhandled for create mutation",
                                               "This indicates something unexpected was returned from the service")
            finish(result: .failure(error))
            return
        case .delete:
            guard !remote.syncMetadata.deleted else {
                log.debug("Conflict Unhandled for data delete in local and remote. Nothing to do, skip processing.")
                finish(result: .success(()))
                return
            }
            // Default conflict resolution is to `discard` the local changes. Since local model has been deleted and
            // remote has not, recreate the local model given the remote data.
            saveCreateOrUpdateMutation(remoteModel: remote)
        case .update:
            guard !remote.syncMetadata.deleted else {
                // Remote model has been deleted and there is nothing we can do to un-delete it
                // Reconcile the local store by deleting locally.
                saveDeleteMutation(remoteModel: remote)
                return
            }

            let localModel: Model
            do {
                localModel = try mutationEvent.decodeModel()
            } catch {
                let error = DataStoreError.unknown("Couldn't get model ", "")
                finish(result: .failure(error))
                return
            }

            let conflictData = DataStoreConclictData(local: localModel, remote: remote.model.instance)
            let latestVersion = remote.syncMetadata.version
            configuration.conflictHandler(conflictData) { result in
                print("result called")
                switch result {
                case .applyRemote:
                    self.saveCreateOrUpdateMutation(remoteModel: remote)
                case .retryLocal:
                    let request = GraphQLRequest<MutationSyncResult>.updateMutation(of: localModel,
                                                                                    version: latestVersion)
                    self.makeAPIRequest(request)
                case .retry(let model):
                    let request = GraphQLRequest<MutationSyncResult>.updateMutation(of: model,
                                                                                    version: latestVersion)
                    self.makeAPIRequest(request)
                }
            }
        }
    }

    // MARK: Sync to cloud

    func makeAPIRequest(_ apiRequest: GraphQLRequest<MutationSync<AnyModel>>) {
        guard let api = api else {
            log.error("\(#function): API unexpectedly nil")
            let apiError = APIError.unknown("API unexpectedly nil", "")
            finish(result: .failure(apiError))
            return
        }
        log.verbose("\(#function) sending mutation with sync data: \(apiRequest)")
        mutationOperation = api.mutate(request: apiRequest) { asyncEvent in
            self.log.verbose("sendMutationToCloud received asyncEvent: \(asyncEvent)")
            self.validateResponseFromCloud(asyncEvent: asyncEvent, request: apiRequest)
        }
    }

    private func validateResponseFromCloud(asyncEvent: AsyncEvent<Void,
        GraphQLResponse<MutationSync<AnyModel>>, APIError>,
                                           request: GraphQLRequest<MutationSync<AnyModel>>) {
        guard !isCancelled else {
            mutationOperation?.cancel()
            let apiError = APIError.unknown("Operation cancelled", "")
            finish(result: .failure(apiError))
            return
        }

        if case .failed(let error) = asyncEvent {
            configuration.errorHandler(error)
        }

        if case .completed(let response) = asyncEvent,
            case .failure(let error) = response {
            configuration.errorHandler(error)
        }

        finish(result: .success(()))
    }

    // MARK: Reconcile Local Store

    private func saveDeleteMutation(remoteModel: MutationSync<AnyModel>) {
        guard let storageAdapter = storageAdapter else {
            Amplify.Logging.log.warn("No storageAdapter, aborting")
            return
        }

        log.verbose(#function)
        let modelName = remoteModel.model.modelName
        let id = remoteModel.model.id

        guard let modelType = ModelRegistry.modelType(from: modelName) else {
            let error = DataStoreError.unknown("Invalid Model \(modelName)", "")
            finish(result: .failure(error))
            return
        }

        storageAdapter.delete(untypedModelType: modelType, withId: id) { response in
            switch response {
            case .failure(let dataStoreError):
                let error = DataStoreError.unknown("Delete failed \(dataStoreError)", "")
                finish(result: .failure(error))
                return
            case .success:
                self.saveMetadata(storageAdapter: storageAdapter, inProcessModel: remoteModel)
            }
        }
    }

    private func saveCreateOrUpdateMutation(remoteModel: MutationSync<AnyModel>) {
        guard let storageAdapter = storageAdapter else {
            Amplify.Logging.log.warn("No storageAdapter, aborting")
            return
        }

        log.verbose(#function)
        storageAdapter.save(untypedModel: remoteModel.model.instance) { response in
            switch response {
            case .failure(let dataStoreError):
                let error = DataStoreError.unknown("Save failed \(dataStoreError)", "")
                self.finish(result: .failure(error))
                return
            case .success(let savedModel):
                let anyModel: AnyModel
                do {
                    anyModel = try savedModel.eraseToAnyModel()
                } catch {
                    let error = DataStoreError.unknown("eraseToAnyModel failed \(error)", "")
                    self.finish(result: .failure(error))
                    return
                }
                let inProcessModel = MutationSync(model: anyModel, syncMetadata: remoteModel.syncMetadata)
                self.saveMetadata(storageAdapter: storageAdapter, inProcessModel: inProcessModel)
            }
        }
    }

    private func saveMetadata(storageAdapter: StorageEngineAdapter,
                              inProcessModel: MutationSync<AnyModel>) {
        log.verbose(#function)
        storageAdapter.save(inProcessModel.syncMetadata, condition: nil) { result in
            switch result {
            case .failure(let dataStoreError):
                let error = DataStoreError.unknown("Save metadata failed \(dataStoreError)", "")
                self.finish(result: .failure(error))
                return
            case .success(let syncMetadata):
                let appliedModel = MutationSync(model: inProcessModel.model, syncMetadata: syncMetadata)
                self.notify(savedModel: appliedModel)
            }
        }
    }

    private func notify(savedModel: MutationSync<AnyModel>) {
        log.verbose(#function)

        guard !isCancelled else {
            log.verbose("\(#function) - cancelled, aborting")
            return
        }

        let mutationType: MutationEvent.MutationType
        let version = savedModel.syncMetadata.version
        if savedModel.syncMetadata.deleted {
            mutationType = .delete
        } else if version == 1 {
            mutationType = .create
        } else {
            mutationType = .update
        }

        // TODO: Dispatch/notify error if we can't erase to any model? Would imply an error in JSON decoding,
        // which shouldn't be possible this late in the process. Possibly notify global conflict/error handler?
        guard let mutationEvent = try? MutationEvent(untypedModel: savedModel.model.instance,
                                                     mutationType: mutationType,
                                                     version: version)
            else {
                log.error("Could not notify mutation event")
                return
        }

        // not this.
        let payload = HubPayload(eventName: HubPayload.EventName.DataStore.syncReceived,
                                 data: mutationEvent)
        Amplify.Hub.dispatch(to: .dataStore, payload: payload)

        mutationEventPublisher.send(mutationEvent)
        // TODO: Still need to figure out how to notify the subscribers.
        finish(result: .success(()))
    }

    override func cancel() {
        mutationOperation?.cancel()
        let error = DataStoreError.unknown("Operation cancelled", "")
        finish(result: .failure(error))
    }

    private func finish(result: Result<Void, Error>) {
        mutationOperation?.removeListener()
        mutationOperation = nil

        DispatchQueue.global().async {
            self.completion(result)
        }
        finish()
    }
}

@available(iOS 13.0, *)
extension ProcessMutationErrorFromCloudOperation: DefaultLogger { }
