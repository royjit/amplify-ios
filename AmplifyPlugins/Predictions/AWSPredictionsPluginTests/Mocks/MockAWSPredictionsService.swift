//
// Copyright 2018-2019 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest
import Foundation
import Amplify
import AWSComprehend
import AWSTranslate
import AWSRekognition
import AWSPolly
import AWSTextract
@testable import AWSPredictionsPlugin

public class MockAWSPredictionsService: AWSTranslateBehavior, AWSPollyBehavior, AWSTextractBehavior, AWSRekognitionBehavior, AWSComprehendBehavior {
    public func translateText(request: AWSTranslateTranslateTextRequest) -> AWSTask<AWSTranslateTranslateTextResponse> {
        <#code#>
    }
    
    public func getTranslate() -> AWSTranslate {
        <#code#>
    }
    
    public func synthesizeSpeech(request: AWSPollySynthesizeSpeechInput) -> AWSTask<AWSPollySynthesizeSpeechOutput> {
        <#code#>
    }
    
    public func getPolly() -> AWSPolly {
        <#code#>
    }
    
    public func analyzeDocument(request: AWSTextractAnalyzeDocumentRequest) -> AWSTask<AWSTextractAnalyzeDocumentResponse> {
        <#code#>
    }
    
    public func detectDocumentText(request: AWSTextractDetectDocumentTextRequest) -> AWSTask<AWSTextractDetectDocumentTextResponse> {
        <#code#>
    }
    
    public func getTextract() -> AWSTextract {
        <#code#>
    }
    
    public func detectLabels(request: AWSRekognitionDetectLabelsRequest) -> AWSTask<AWSRekognitionDetectLabelsResponse> {
        <#code#>
    }
    
    public func detectCelebs(request: AWSRekognitionRecognizeCelebritiesRequest) -> AWSTask<AWSRekognitionRecognizeCelebritiesResponse> {
        <#code#>
    }
    
    public func detectText(request: AWSRekognitionDetectTextRequest) -> AWSTask<AWSRekognitionDetectTextResponse> {
        <#code#>
    }
    
    public func detectFaces(request: AWSRekognitionDetectFacesRequest) -> AWSTask<AWSRekognitionDetectFacesResponse> {
        <#code#>
    }
    
    public func detectModerationLabels(request: AWSRekognitionDetectModerationLabelsRequest) -> AWSTask<AWSRekognitionDetectModerationLabelsResponse> {
        <#code#>
    }
    
    public func detectFacesFromCollection(request: AWSRekognitionSearchFacesByImageRequest) -> AWSTask<AWSRekognitionSearchFacesByImageResponse> {
        <#code#>
    }
    
    public func getRekognition() -> AWSRekognition {
        <#code#>
    }
    
    public func detectSentiment(request: AWSComprehendDetectSentimentRequest) -> AWSTask<AWSComprehendDetectSentimentResponse> {
        <#code#>
    }
    
    public func detectEntities(request: AWSComprehendDetectEntitiesRequest) -> AWSTask<AWSComprehendDetectEntitiesResponse> {
        <#code#>
    }
    
    public func detectLanguage(request: AWSComprehendDetectDominantLanguageRequest) -> AWSTask<AWSComprehendDetectDominantLanguageResponse> {
        <#code#>
    }
    
    public func detectSyntax(request: AWSComprehendDetectSyntaxRequest) -> AWSTask<AWSComprehendDetectSyntaxResponse> {
        <#code#>
    }
    
    public func detectKeyPhrases(request: AWSComprehendDetectKeyPhrasesRequest) -> AWSTask<AWSComprehendDetectKeyPhrasesResponse> {
        <#code#>
    }
    
    public func getComprehend() -> AWSComprehend {
        <#code#>
    }
    
    
   
    
    
}
