import Foundation
import TelegramCore
import RichTextEditorCore

/// A pill is an ATOM in the instant-page layout: its label lives inside the button, so the carrying
/// run's text (a single U+FFFC placeholder) is dropped and the whole run becomes a `RichText.textButton`.
func instantPageButton(from ref: ButtonRef) -> InstantPageButton {
    InstantPageButton(
        text: richText(from: ref.label),
        action: replyMarkupButtonAction(from: ref.action),
        color: ref.color.map(replyMarkupColor(from:)),
        isLink: ref.isLink
    )
}

/// Map a single text run to inline `RichText`, applying its character attributes as nested wrappers.
func richText(from run: TextRun) -> RichText? {
    let attributes = run.attributes
    if let button = attributes.button {
        return .textButton(instantPageButton(from: button))
    }
    var result: RichText
    if let formula = attributes.formula {
        result = .formula(latex: formula)
    } else if let emoji = attributes.emoji {
        // v1: custom emoji has no backing file here — emit its alt text as plain text.
        let alt = emoji.altText ?? ""
        if alt.isEmpty {
            return nil
        }
        result = .plain(alt)
    } else if run.text.isEmpty {
        return nil
    } else {
        result = .plain(run.text)
    }
    if attributes.inlineCode {
        result = .fixed(result)
    }
    if attributes.strikethrough {
        result = .strikethrough(result)
    }
    if attributes.underline {
        result = .underline(result)
    }
    if attributes.italic {
        result = .italic(result)
    }
    if attributes.bold {
        result = .bold(result)
    }
    if attributes.highlight != nil {
        result = .marked(result)
    }
    if let link = attributes.link {
        result = .url(text: result, url: link, webpageId: nil)
    }
    return result
}

/// Map a run array to one `RichText` (`.concat` when multiple, `.empty` when none).
func richText(from runs: [TextRun]) -> RichText {
    let parts = runs.compactMap(richText(from:))
    if parts.isEmpty {
        return .empty
    }
    if parts.count == 1 {
        return parts[0]
    }
    return .concat(parts)
}
