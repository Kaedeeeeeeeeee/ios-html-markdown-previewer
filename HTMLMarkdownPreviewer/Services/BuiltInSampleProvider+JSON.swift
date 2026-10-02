import Foundation

extension BuiltInSampleProvider {
    /// Deliberately includes an integer beyond JavaScript's safe range. Structure
    /// preview and field copying must preserve its exact original digits.
    static let jsonSample = #"""
    {
      "status": "ok",
      "requestId": 9007199254740993,
      "report": {
        "title": "A week of reading",
        "published": true,
        "minutes": 247,
        "languages": ["English", "日本語", "中文"],
        "nextPage": null
      },
      "chapters": [
        {"title": "Notes", "pages": 12},
        {"title": "Reports", "pages": 8},
        {"title": "Configuration", "pages": 3}
      ],
      "settings": {
        "theme": "system",
        "fontScale": 1.25,
        "offline": true
      }
    }
    """#
}
