import Foundation

enum PackageSampleStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "PackageSample", bundle: .main, value: fallback, comment: "")
    }

    static let contents = text("contents", "Inside this report")
    static let overview = text("overview", "Weekly overview")
    static let backToOverview = text("backToOverview", "Back to overview")
    static let detailsTitle = text("detailsTitle", "Reading in detail")
    static let detailsLinkTitle = text("detailsLinkTitle", "Read the details")
    static let detailsLinkCaption = text("detailsLinkCaption", "Daily rhythm and a closer look at the week")
    static let notesTitle = text("notesTitle", "Notes & method")
    static let notesLinkCaption = text("notesLinkCaption", "The ideas and calculation behind the report")
    static let detailsEyebrow = text("detailsEyebrow", "CHAPTER 02 · READING JOURNAL")
    static let detailsIntro = text("detailsIntro", "Small pockets of time add up. Here is how a week of reading became a habit.")
    static let average = text("average", "Daily average")
    static let longest = text("longest", "Longest session")
    static let minutes = text("minutes", "min")
    static let dailyHeading = text("dailyHeading", "Seven days, one steady rhythm")
    static let day = text("day", "Day")
    static let duration = text("duration", "Reading time")
    static let takeaway = text("takeaway", "What worked")
    static let takeawayBody = text("takeawayBody", "The longest session happened on Saturday, but the short weekday sessions mattered just as much. A book within reach made starting easier.")
    static let continueReading = text("continueReading", "Continue to the notes")
    static let detailsFooter = text("detailsFooter", "A closer look, without leaving the report.")
    static let notesIntro = text("notesIntro", "A few observations to carry into next week, followed by the simple calculation used in this report.")
    static let notesQuote = text("notesQuote", "The best reading plan is the one that leaves room for curiosity.")
    static let nextHeading = text("nextHeading", "For the coming week")
    static let nextOne = text("nextOne", "Keep a book beside the morning coffee.")
    static let nextTwo = text("nextTwo", "Save one sentence after each reading session.")
    static let nextThree = text("nextThree", "Leave the weekend session open-ended.")
    static let methodHeading = text("methodHeading", "How the average is calculated")
    static let methodIntro = text("methodIntro", "Add the seven daily reading times, then divide by seven. The result is rounded to one decimal place.")
    static let codeHeading = text("codeHeading", "The same idea in code")
    static let viewDetails = text("viewDetails", "View the daily details")
}
