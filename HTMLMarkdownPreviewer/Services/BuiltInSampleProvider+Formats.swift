import Foundation

extension BuiltInSampleProvider {
    /// A standalone Mermaid file, as an agent would save it.
    static let mermaidSample = """
    ---
    title: How an agent finishes a task
    ---
    flowchart TD
        Request([Request from you]) --> Plan[Read the files and make a plan]
        Plan --> Work[Edit code and run checks]
        Work --> Check{Do the tests pass?}
        Check -- No --> Fix[Read the failure and fix it]
        Fix --> Work
        Check -- Yes --> Report[Write a summary and open a PR]
        Report --> Review([You review it on your phone])
    """

    /// Covers a quoted field with a comma, an empty cell, and numeric columns
    /// that the table aligns to the right.
    static let csvSample = """
    Task,Model,Accuracy (%),Median time (s),Cost (USD),Notes
    Summarize a report,Model A,92.4,3.1,0.012,Kept every heading
    Summarize a report,Model B,88.9,2.4,0.008,
    Fix a failing test,Model A,81.0,41.7,0.210,"Found the root cause, then added a test"
    Fix a failing test,Model B,73.5,35.2,0.150,Needed one retry
    Translate a README,Model A,95.8,6.9,0.031,
    Translate a README,Model B,94.1,5.6,0.022,Kept code blocks as is
    Draw a diagram,Model A,89.3,4.4,0.019,Mermaid flowchart
    Draw a diagram,Model B,85.0,3.8,0.014,"Used a sequence diagram instead"
    """

    /// Self-contained: no scripts, links, fonts, or external images.
    static let svgSample = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 400" font-family="-apple-system, Helvetica, Arial, sans-serif">
      <rect width="640" height="400" rx="24" fill="#ffffff"/>
      <text x="40" y="58" font-size="26" font-weight="700" fill="#1d1d1f">Reading this week</text>
      <text x="40" y="88" font-size="16" fill="#6e6e73">Minutes per day</text>
      <g stroke="#e5e5ea" stroke-width="1">
        <line x1="40" y1="330" x2="600" y2="330"/>
        <line x1="40" y1="260" x2="600" y2="260"/>
        <line x1="40" y1="190" x2="600" y2="190"/>
        <line x1="40" y1="120" x2="600" y2="120"/>
      </g>
      <g fill="#0a84ff">
        <rect x="60" y="230" width="52" height="100" rx="8"/>
        <rect x="140" y="190" width="52" height="140" rx="8"/>
        <rect x="220" y="250" width="52" height="80" rx="8"/>
        <rect x="300" y="150" width="52" height="180" rx="8"/>
        <rect x="380" y="210" width="52" height="120" rx="8"/>
        <rect x="460" y="130" width="52" height="200" rx="8" fill="#ff9f0a"/>
        <rect x="540" y="170" width="52" height="160" rx="8"/>
      </g>
      <g font-size="14" fill="#6e6e73" text-anchor="middle">
        <text x="86" y="356">Mon</text><text x="166" y="356">Tue</text><text x="246" y="356">Wed</text>
        <text x="326" y="356">Thu</text><text x="406" y="356">Fri</text><text x="486" y="356">Sat</text>
        <text x="566" y="356">Sun</text>
      </g>
      <text x="486" y="118" font-size="15" font-weight="600" fill="#ff9f0a" text-anchor="middle">58 min</text>
    </svg>
    """
}
