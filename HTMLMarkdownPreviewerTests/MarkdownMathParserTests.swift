import XCTest
@testable import HTMLMarkdownPreviewer

final class MarkdownMathParserTests: XCTestCase {
    func testInlineDelimitersPreserveLaTeXAndUnicode() throws {
        let document = MarkdownRenderService().render(markdown: #"面積 $a_b^2 + \frac{α}{β}$ と \(\sqrt{x_1}\) です。"#)
        let paragraph = try paragraph(in: document)
        XCTAssertEqual(math(in: paragraph), [#"a_b^2 + \frac{α}{β}"#, #"\sqrt{x_1}"#])
        XCTAssertEqual(String(paragraph.characters), #"面積 a_b^2 + \frac{α}{β} と \sqrt{x_1} です。"#)
        XCTAssertFalse(paragraph.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
    }

    func testDisplayMathSupportsMultilineAlignedAndBracketDelimiters() {
        let document = MarkdownRenderService().render(markdown: #"""
        $$
        \begin{aligned}
        a_b &= \frac{1}{2} \\
        c &= \sqrt{d}
        \end{aligned}
        $$

        \[e^{i\pi}+1=0\]
        """#)
        XCTAssertEqual(document.blocks, [
            .mathBlock("\n" + #"""
            \begin{aligned}
            a_b &= \frac{1}{2} \\
            c &= \sqrt{d}
            \end{aligned}
            """# + "\n"),
            .mathBlock(#"e^{i\pi}+1=0"#)
        ])
    }

    func testSameLineDisplayMathSplitsProseAndEqualAdjacentFormulas() {
        let document = MarkdownRenderService().render(markdown: "Before $$x$$ after.\n\n$$y$$$$y$$")
        XCTAssertEqual(document.blocks, [
            .paragraph(AttributedString("Before ")), .mathBlock("x"), .paragraph(AttributedString(" after.")),
            .mathBlock("y"), .mathBlock("y")
        ])
    }

    func testFencedMathAndMermaidKeepOriginalSource() {
        let document = MarkdownRenderService().render(markdown: #"""
        ```math
        \frac{a_b}{c_d}
        ```

        ```mermaid
        flowchart LR
          A["$5"] --> B
        ```
        """#)
        XCTAssertEqual(document.blocks, [
            .mathBlock(#"\frac{a_b}{c_d}"# + "\n"),
            .codeBlock(language: "mermaid", code: "flowchart LR\n  A[\"$5\"] --> B\n")
        ])
    }

    func testCodeEscapesAndCurrencyAreLiteral() throws {
        let document = MarkdownRenderService().render(markdown: #"""
        Cost $5 and $10. Escaped \$x\$. Inline `$a_b$` and ``\(x\)``.

            $indented$

        ```text
        $$fenced$$
        \[also fenced\]
        ```
        """#)
        let paragraph = try paragraph(in: document)
        XCTAssertTrue(math(in: paragraph).isEmpty)
        XCTAssertEqual(String(paragraph.characters), #"Cost $5 and $10. Escaped $x$. Inline $a_b$ and \(x\)."#)
        XCTAssertEqual(document.blocks[1], .codeBlock(language: nil, code: "$indented$\n"))
        XCTAssertEqual(document.blocks[2], .codeBlock(language: "text", code: #"$$fenced$$"# + "\n" + #"\[also fenced\]"# + "\n"))
    }

    func testBackslashParityAndEscapedDollarInsideMath() throws {
        let paragraph = try paragraph(in: MarkdownRenderService().render(markdown: #"\\$x$ and $\text{price }\$5$ and \\\(y\)"#))
        XCTAssertEqual(math(in: paragraph), ["x", #"\text{price }\$5"#, "y"])
        XCTAssertEqual(String(paragraph.characters), #"\x and \text{price }\$5 and \y"#)
    }

    func testNumericMathAndInvalidWhitespaceBoundaries() throws {
        let paragraph = try paragraph(in: MarkdownRenderService().render(markdown: #"$2 + 2$; $ 5$; $x $; $x$10; $z$"#))
        XCTAssertEqual(math(in: paragraph), ["2 + 2", "z"])
        XCTAssertTrue(String(paragraph.characters).contains("$ 5$; $x $; $x$10"))
    }

    func testMathInsideHeadingsTablesListsAndQuotes() throws {
        let document = MarkdownRenderService().render(markdown: #"""
        # Formula $E=mc^2$

        | $x_i$ | Value |
        | --- | --- |
        | $\lvert x\rvert$ | $a|b$ |

        - Label $x$
          - Nested \(y\)

        > $$
        > \frac{a}{b}
        > $$
        """#)
        guard case .heading(_, let title) = document.blocks[0],
              case .table(let table) = document.blocks[1],
              case .unorderedList(let list) = document.blocks[2],
              case .blockQuote(let quote) = document.blocks[3] else {
            return XCTFail("Expected the original Markdown block structure.")
        }
        XCTAssertEqual(math(in: title), ["E=mc^2"])
        XCTAssertEqual(math(in: table.header[0]), ["x_i"])
        XCTAssertEqual(math(in: table.rows[0][0]), [#"\lvert x\rvert"#])
        XCTAssertEqual(math(in: table.rows[0][1]), ["a|b"])
        XCTAssertEqual(math(in: list[0].text), ["x"])
        guard case .unorderedList(let children) = list[0].children.first else { return XCTFail("Expected nested list.") }
        XCTAssertEqual(math(in: children[0].text), ["y"])
        XCTAssertEqual(quote, [.mathBlock("\n" + #"\frac{a}{b}"# + "\n")])
    }

    func testDestinationsURLsReferencesAndHTMLNeverBecomeMath() throws {
        let document = MarkdownRenderService().render(markdown: #"""
        [$x$](https://example.com/$route$) https://example.com/$path$ <$person@example.com> [reference][id]

        [id]: https://example.com/$ref$

        <script>$injection$</script>
        """#)
        let paragraph = try paragraph(in: document)
        XCTAssertEqual(math(in: paragraph), ["x"])
        XCTAssertTrue(paragraph.runs.contains { $0.link?.absoluteString == "https://example.com/$route$" })
        XCTAssertTrue(paragraph.runs.contains { $0.link?.absoluteString == "https://example.com/$ref$" })
        XCTAssertFalse(String(paragraph.characters).contains("MDMATH"))
        for block in document.blocks.dropFirst() {
            if case .paragraph(let text) = block { XCTAssertTrue(math(in: text).isEmpty) }
        }
    }

    func testUnclosedAndEmptyMathRemainReadable() throws {
        for input in [#"Unclosed $a_b"#, #"Unclosed \(a_b"#, #"Unclosed \[x"#, "$$", "$$ $$", #"\(\)"#] {
            let document = MarkdownRenderService().render(markdown: input)
            let paragraph = try paragraph(in: document)
            XCTAssertTrue(math(in: paragraph).isEmpty, input)
            XCTAssertEqual(String(paragraph.characters), input, input)
        }
    }

    func testMultilineReferenceDefinitionDoesNotLeakPlaceholdersIntoURLs() throws {
        let document = MarkdownRenderService().render(markdown: #"""
        [$x$][formula]

        [formula]:
          /notes/$section$/index.html
          "Formula $title$"
        """#)
        let paragraph = try paragraph(in: document)
        XCTAssertEqual(math(in: paragraph), ["x"])
        XCTAssertEqual(paragraph.link?.absoluteString, "/notes/$section$/index.html")
    }

    func testNestedCodeAndDisplayMathRetainListStructure() throws {
        let document = MarkdownRenderService().render(markdown: #"""
        > Code `$inline$`
        >
        > ```text
        > $code$
        > ```

        - $$
          x_i + y_i
          $$
        - Normal $z$
        """#)
        guard case .blockQuote(let quote) = document.blocks[0],
              case .paragraph(let text) = quote[0],
              case .unorderedList(let list) = document.blocks[1] else {
            return XCTFail("Expected quote and list.")
        }
        XCTAssertTrue(math(in: text).isEmpty)
        XCTAssertEqual(quote[1], .codeBlock(language: "text", code: "$code$\n"))
        XCTAssertEqual(list[0].children, [.mathBlock("\nx_i + y_i\n")])
        XCTAssertEqual(math(in: list[1].text), ["z"])
    }

    func testFormulaSourceIsSearchableAndRenderIsDeterministic() throws {
        let source = #"# Heading $α_i$"# + "\n\n" + #"$$\frac{α_i}{2}$$"#
        let first = MarkdownRenderService().render(markdown: source)
        XCTAssertEqual(first, MarkdownRenderService().render(markdown: source))
        let index = MarkdownReadingIndex(document: first)
        XCTAssertEqual(index.headings.map(\.title), ["Heading α_i"])
        XCTAssertEqual(index.matches(for: "α_i").count, 2)
        XCTAssertEqual(index.matches(for: #"\frac"#).count, 1)
        XCTAssertEqual(index.matches(for: "MDMATH").count, 0)
    }

    func testFormulaCannotCreateMarkdownOrHTMLNodes() throws {
        let source = #"$\text{<script>alert(1)</script> **bold** [x](https://invalid.example)}$"#
        let paragraph = try paragraph(in: MarkdownRenderService().render(markdown: source))
        XCTAssertEqual(math(in: paragraph), [String(source.dropFirst().dropLast())])
        XCTAssertNil(paragraph.link)
        XCTAssertNil(paragraph.inlinePresentationIntent)
        XCTAssertEqual(String(paragraph.characters), String(source.dropFirst().dropLast()))
    }

    func testPlaceholderLookingTextCannotInjectAnotherRendersFormula() throws {
        let oldToken = MarkdownMathParser("$secret$").markdown
        let paragraph = try paragraph(in: MarkdownRenderService().render(markdown: oldToken + " and $visible$"))
        XCTAssertEqual(String(paragraph.characters), oldToken + " and visible")
        XCTAssertEqual(math(in: paragraph), ["visible"])
    }

    func testLongUnclosedDelimiterSequenceRemainsLiteral() throws {
        let source = String(repeating: #"\("#, count: 2_000)
        let paragraph = try paragraph(in: MarkdownRenderService().render(markdown: source))
        XCTAssertEqual(String(paragraph.characters), source)
        XCTAssertTrue(math(in: paragraph).isEmpty)
    }

    private func paragraph(in document: MarkdownDocument) throws -> AttributedString {
        let first = try XCTUnwrap(document.blocks.first)
        guard case .paragraph(let paragraph) = first else {
            XCTFail("Expected paragraph, got \(first)")
            return AttributedString()
        }
        return paragraph
    }

    private func math(in text: AttributedString) -> [String] {
        text.runs.compactMap { $0[MarkdownMathAttribute.self] }
    }
}
