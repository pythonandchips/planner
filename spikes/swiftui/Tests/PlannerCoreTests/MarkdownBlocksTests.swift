import Testing
@testable import PlannerCore

@Suite struct MarkdownBlocksTests {
    @Test func splitsCommonBlocks() {
        let md = """
        # Iteration 1

        Some **bold** text
        on two lines.

        - one
          continued
        - [ ] todo
        1. first

        ```ruby
        puts 1
        ```
        > quoted
        | a | b |
        |---|---|
        ---
        """
        #expect(MarkdownBlocks.parse(md) == [
            .heading(level: 1, text: "Iteration 1"),
            .paragraph("Some **bold** text\non two lines."),
            .listItem(indent: 0, marker: "•", text: "one continued"),
            .listItem(indent: 0, marker: "☐", text: "todo"),
            .listItem(indent: 0, marker: "1.", text: "first"),
            .code(language: "ruby", text: "puts 1"),
            .quote("quoted"),
            .table(["| a | b |", "|---|---|"]),
            .rule,
        ])
    }
}
