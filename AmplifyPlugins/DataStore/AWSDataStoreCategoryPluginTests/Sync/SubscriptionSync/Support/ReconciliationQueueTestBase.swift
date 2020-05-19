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
@testable import AWSDataStoreCategoryPlugin
@testable import AWSPluginsCore

class ReconciliationQueueTestBase: XCTestCase {

    var apiPlugin: MockAPICategoryPlugin!
    var authPlugin: MockAuthCategoryPlugin!
    var storageAdapter: MockSQLiteStorageEngineAdapter!
    var subscriptionEventsPublisher: MockIncomingSubscriptionEventPublisher!
    var subscriptionEventsSubject: PassthroughSubject<IncomingSubscriptionEventPublisherEvent, DataStoreError>!

    override func setUp() {
        ModelRegistry.register(modelType: MockSynced.self)

        apiPlugin = MockAPICategoryPlugin()
        authPlugin = MockAuthCategoryPlugin()

        storageAdapter = MockSQLiteStorageEngineAdapter()
        subscriptionEventsPublisher = MockIncomingSubscriptionEventPublisher()
        subscriptionEventsSubject = subscriptionEventsPublisher.subject
    }

}

struct MockIncomingSubscriptionEventPublisher: IncomingSubscriptionEventPublisher {
    let subject = PassthroughSubject<IncomingSubscriptionEventPublisherEvent, DataStoreError>()

    var publisher: AnyPublisher<IncomingSubscriptionEventPublisherEvent, DataStoreError> {
        subject.eraseToAnyPublisher()
    }

    func cancel() {
        //no-op for mock
    }
}
