//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

extension AmplifyAPICategory: APICategoryGraphQLBehavior {

    // MARK: - Model-based GraphQL Operations

    public func query<M: Model, E: Decodable>(from modelType: M.Type,
                                              byId id: String,
                                              listener: GraphQLOperation<M?, E>.EventListener?) -> GraphQLOperation<M?, E> {
        plugin.query(from: modelType, byId: id, listener: listener)
    }

    public func query<M: Model, E: Decodable>(from modelType: M.Type,
                                              where predicate: QueryPredicate?,
                                              listener: GraphQLOperation<[M], E>.EventListener?) -> GraphQLOperation<[M], E> {
        plugin.query(from: modelType, where: predicate, listener: listener)
    }

    public func mutate<M: Model, E: Decodable>(of model: M,
                                               type: GraphQLMutationType,
                                               listener: GraphQLOperation<M, E>.EventListener?) -> GraphQLOperation<M, E> {
        plugin.mutate(of: model, type: type, listener: listener)
    }

    public func subscribe<M: Model, E: Decodable>(from modelType: M.Type,
                                                  type: GraphQLSubscriptionType,
                                                  listener: GraphQLSubscriptionOperation<M, E>.EventListener?)
        -> GraphQLSubscriptionOperation<M, E> {
            plugin.subscribe(from: modelType, type: type, listener: listener)
    }

    // MARK: - Request-based GraphQL operations

    public func query<R: Decodable, E: Decodable>(request: GraphQLRequest<R, E>,
                                                  listener: GraphQLOperation<R, E>.EventListener?) -> GraphQLOperation<R, E> {
        plugin.query(request: request, listener: listener)
    }

    public func mutate<R: Decodable, E: Decodable>(request: GraphQLRequest<R, E>,
                                                   listener: GraphQLOperation<R, E>.EventListener?) -> GraphQLOperation<R, E> {
        plugin.mutate(request: request, listener: listener)
    }

    public func subscribe<R, E: Decodable>(request: GraphQLRequest<R, E>,
                                           listener: GraphQLSubscriptionOperation<R, E>.EventListener?)
        -> GraphQLSubscriptionOperation<R, E> {
            plugin.subscribe(request: request, listener: listener)
    }
}
