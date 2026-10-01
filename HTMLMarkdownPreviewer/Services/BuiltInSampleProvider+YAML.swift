import Foundation

extension BuiltInSampleProvider {
    static let yamlSample = """
    # Local app configuration — comments stay in Source.
    app:
      name: HTML Previewer
      version: "1.5"
      offline: true
      languages:
        - English
        - 中文
        - 日本語

    services:
      web:
        port: 8080
        enabled: true
        description: |
          Preview documents on this device.
          Keep the original file ready to share.

    defaults: &reading
      font_size: 17
      theme: system
    reader: *reading

    ---
    # A second document in the same YAML file.
    profile: development
    services:
      web:
        port: 3000
        enabled: false
    tags: [preview, local, yaml]
    """
}
