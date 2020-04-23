//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Amplify

extension MockAPICategoryPlugin {
    enum ResponderKeys {
        case queryRequestListener
        case subscribeRequestListener
        case mutateRequestListener
    }
}

typealias QueryRequestListenerResponder<R: Decodable, E: Decodable> =
    MockResponder<(GraphQLRequest<R>, GraphQLOperation<R, E>.EventListener?), GraphQLOperation<R, E>?>

typealias SubscribeRequestListenerResponder<R: Decodable, E: Decodable> =
    MockResponder<(GraphQLRequest<R>, GraphQLSubscriptionOperation<R, E>.EventListener?), GraphQLSubscriptionOperation<R, E>?>

typealias MutateRequestListenerResponder<R: Decodable, E: Decodable> =
    MockResponder<(GraphQLRequest<R>, GraphQLOperation<R, E>.EventListener?), GraphQLOperation<R, E>?>
