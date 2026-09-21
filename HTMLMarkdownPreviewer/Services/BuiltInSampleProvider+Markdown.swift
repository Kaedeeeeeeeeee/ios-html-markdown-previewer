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

        ## \(AppStrings.SampleDesign.markdownCodeHeading)

        ```text
        pages: 10
        notifications: off
        ```

        ---

        *\(AppStrings.SampleDesign.markdownFooter)*
        """
    }
}
