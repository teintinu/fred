import Foundation

enum DeepseekModel: String {
    case chat = "deepseek-chat"
    case reasoner = "deepseek-reasoner"
}

struct DeepseekMessage: Codable {
    var role: String
    var content: String
}

struct DeepseekRequest: Codable {
    struct ResponseFormat: Codable {
        var type: String
    }

    var model: String
    var messages: [DeepseekMessage]
    var temperature: Double?
    var response_format: ResponseFormat?
}

struct DeepseekResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            var content: String?
        }
        var message: Message
    }
    struct ErrorBody: Codable {
        var message: String?
    }

    var choices: [Choice]
    var error: ErrorBody?
}
