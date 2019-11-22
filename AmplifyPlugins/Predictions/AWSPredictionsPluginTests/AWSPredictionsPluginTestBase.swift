//
// Copyright 2018-2019 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest
import Amplify
@testable import AWSPredictionsPlugin
@testable import AmplifyTestCommon

class AWSPredictionsPluginTests: XCTestCase {
    var predictionsPlugin: AWSPredictionsPlugin!
    var predictionsService: MockAWSPredictionsService!
    var authService: MockAWSAuthService!
    var queue: MockOperationQueue!
    let testExpires = 10

    override func setUp() {
        predictionsPlugin = AWSPredictionsPlugin()
        predictionsService = MockAWSPredictionsService()
        authService = MockAWSAuthService()
        queue = MockOperationQueue()

       // predictionsPlugin.configure(
    }
}
