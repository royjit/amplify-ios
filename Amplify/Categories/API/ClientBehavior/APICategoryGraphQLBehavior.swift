//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// Behavior of the API category related to GraphQL operations
public protocol APICategoryGraphQLBehavior: class {

    // MARK: - Model-based GraphQL Operations

    /// Perform a GraphQL query for a single `Model` item. This operation will be asychronous, with the callback
    /// accessible both locally and via the Hub.
    ///
    /// - Parameters:
    ///   - modelType: The type for the item returned
    ///   - id: Unique identifier of the item to retrieve
    ///   - listener: The event listener for the operation
    /// - Returns: The AmplifyOperation being enqueued.
    func query<M: Model, E: Decodable>(from modelType: M.Type,
                                       byId id: String,
                                       listener: GraphQLOperation<M?, E>.EventListener?) -> GraphQLOperation<M?, E>

    /// Performs a GraphQL query for a list of `Model` items which satisfies the `predicate`. This operation will be
    /// asychronous, with the callback accessible both locally and via the Hub.
    ///
    /// - Parameters:
    ///   - modelType: The type for the items returned
    ///   - predicate: The filter for which items to query
    ///   - listener: The event listener for the operation
    /// - Returns: The AmplifyOperation being enqueued.
    func query<M: Model, E: Decodable>(from modelType: M.Type,
                                       where predicate: QueryPredicate?,
                                       listener: GraphQLOperation<[M], E>.EventListener?) -> GraphQLOperation<[M], E>

    /// Performs a GraphQL mutate for the `Model` item. This operation will be asynchronous, with the callback
    /// accessible both locally and via the Hub.
    ///
    /// - Parameters:
    ///   - model: The instance of the `Model`.
    ///   - type: The type of mutation to apply on the instance of `Model`.
    ///   - listener: The event listener for the operation
    /// - Returns: The AmplifyOperation being enqueued.
    func mutate<M: Model, E: Decodable>(of model: M,
                                        type: GraphQLMutationType,
                                        listener: GraphQLOperation<M, E>.EventListener?) -> GraphQLOperation<M, E>

    /// Performs a GraphQL subscribe operation for `Model` items.
    ///
    /// - Parameters:
    ///   - modelType: The type of items to be subscribed to
    ///   - type: The type of subscription for the items
    ///   - listener: The event listener for the operation
    /// - Returns: The AmplifyOperation being enqueued.
    func subscribe<M: Model, E: Decodable>(from modelType: M.Type,
                                           type: GraphQLSubscriptionType,
                                           listener: GraphQLSubscriptionOperation<M, E>.EventListener?)
        -> GraphQLSubscriptionOperation<M, E>

    // MARK: - Request-based GraphQL Operations

    /// Perform a GraphQL query operation against a previously configured API. This operation
    /// will be asynchronous, with the callback accessible both locally and via the Hub.
    ///
    /// - Parameters:
    ///   - request: The GraphQL request containing apiName, document, variables, and responseType
    ///   - listener: The event listener for the operation
    /// - Returns: The AmplifyOperation being enqueued
    func query<R: Decodable, E: Decodable>(request: GraphQLRequest<R, E>,
                                           listener: GraphQLOperation<R, E>.EventListener?) -> GraphQLOperation<R, E>

    /// Perform a GraphQL mutate operation against a previously configured API. This operation
    /// will be asynchronous, with the callback accessible both locally and via the Hub.
    ///
    /// - Parameters:
    ///   - request: The GraphQL request containing apiName, document, variables, and responseType
    ///   - listener: The event listener for the operation
    /// - Returns: The AmplifyOperation being enqueued
    func mutate<R: Decodable, E: Decodable>(request: GraphQLRequest<R, E>,
                                            listener: GraphQLOperation<R, E>.EventListener?) -> GraphQLOperation<R, E>

    /// Perform a GraphQL subscribe operation against a previously configured API. This operation
    /// will be asychronous, with the callback accessible both locally and via the Hub.
    ///
    /// - Parameters:
    ///   - request: The GraphQL request containing apiName, document, variables, and responseType
    ///   - listener: The event listener for the operation
    /// - Returns: The AmplifyOperation being enqueued
    func subscribe<R: Decodable, E: Decodable>(request: GraphQLRequest<R, E>,
                                               listener: GraphQLSubscriptionOperation<R, E>.EventListener?)
        -> GraphQLSubscriptionOperation<R, E>
}
