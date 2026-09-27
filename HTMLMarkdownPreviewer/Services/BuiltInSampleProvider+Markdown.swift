import Foundation

extension BuiltInSampleProvider {
    static var markdownSample: String {
        """
        # \(AppStrings.SampleDesign.markdownTitle)

        \(AppStrings.SampleDesign.markdownIntro)

        > \(AppStrings.SampleDesign.markdownQuote)

        ## \(AppStrings.SampleDesign.markdownSection)

        \(AppStrings.SampleDesign.markdownParagraph)

        - \(AppStrings.SampleDesign.markdownBulletOne)
        - \(AppStrings.SampleDesign.markdownBulletTwo)

        ## \(AppStrings.SampleDesign.markdownTableHeading)

        | \(AppStrings.SampleDesign.markdownDay) | \(AppStrings.SampleDesign.markdownPages) | \(AppStrings.SampleDesign.markdownNoteColumn) |
        | :--- | ---: | :--- |
        | \(AppStrings.SampleDesign.markdownDayOne) | 12 | \(AppStrings.SampleDesign.markdownThoughtOne) |
        | \(AppStrings.SampleDesign.markdownDayTwo) | 18 | \(AppStrings.SampleDesign.markdownThoughtTwo) |
        | \(AppStrings.SampleDesign.markdownDayThree) | 24 | \(AppStrings.SampleDesign.markdownThoughtThree) |

        ## \(AppStrings.SampleDesign.markdownNextHeading)

        1. \(AppStrings.SampleDesign.markdownNextOne)
        2. \(AppStrings.SampleDesign.markdownNextTwo)

        ## \(MarkdownEnhancementStrings.codeHeading)

        \(MarkdownEnhancementStrings.codeIntro)

        ```swift
        let pages = [12, 18, 24]
        let total = pages.reduce(0, +)
        print("Read \\(total) pages")
        ```

        ## \(MarkdownEnhancementStrings.mathHeading)

        \(MarkdownEnhancementStrings.mathIntro)

        $$
        \\int_0^1 x^2\\,dx = \\frac{1}{3}
        $$

        ## \(MarkdownEnhancementStrings.diagramHeading)

        \(MarkdownEnhancementStrings.diagramIntro)

        ```mermaid
        flowchart LR
            A["\(MarkdownEnhancementStrings.diagramStart)"] --> B["\(MarkdownEnhancementStrings.diagramRead)"]
            B --> C["\(MarkdownEnhancementStrings.diagramShare)"]
        ```

        ---

        *\(AppStrings.SampleDesign.markdownFooter)*
        """
    }
}
