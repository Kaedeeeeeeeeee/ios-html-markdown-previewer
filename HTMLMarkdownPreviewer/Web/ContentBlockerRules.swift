import Foundation

enum ContentBlockerRules {
    static let externalNetworkIdentifier = "external-network-blocker-v1"

    static let externalNetworkRules = """
    [
      {
        "trigger": {
          "url-filter": "^https?://.*"
        },
        "action": {
          "type": "block"
        }
      }
    ]
    """
}

