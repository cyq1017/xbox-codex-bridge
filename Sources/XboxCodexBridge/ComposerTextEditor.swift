import Foundation

enum ComposerEditCommand: String {
  case moveLeft = "composerMoveLeft"
  case moveRight = "composerMoveRight"
  case moveToLineStart = "composerMoveLineStart"
  case moveToLineEnd = "composerMoveLineEnd"
  case selectLeft = "composerSelectLeft"
  case selectRight = "composerSelectRight"
  case selectToLineStart = "composerSelectLineStart"
  case selectToLineEnd = "composerSelectLineEnd"
  case deleteBackward = "composerDeleteBackward"
}

struct ComposerTextState: Equatable {
  let text: String
  let selection: NSRange
}

enum ComposerTextEditor {
  static func apply(_ command: ComposerEditCommand, to state: ComposerTextState)
    -> ComposerTextState
  {
    let text = state.text as NSString
    let selection = normalized(state.selection, textLength: text.length)

    switch command {
    case .moveLeft:
      let position =
        selection.length > 0
        ? selection.location
        : characterBefore(selection.location, in: text)?.location ?? selection.location
      return result(text, selection: NSRange(location: position, length: 0))
    case .moveRight:
      let position =
        selection.length > 0
        ? NSMaxRange(selection)
        : characterAfter(NSMaxRange(selection), in: text).map(NSMaxRange) ?? NSMaxRange(selection)
      return result(text, selection: NSRange(location: position, length: 0))
    case .moveToLineStart:
      return result(
        text,
        selection: NSRange(location: lineStart(at: selection.location, in: text), length: 0)
      )
    case .moveToLineEnd:
      return result(
        text,
        selection: NSRange(location: lineEnd(at: NSMaxRange(selection), in: text), length: 0)
      )
    case .selectLeft:
      guard let character = characterBefore(selection.location, in: text) else {
        return result(text, selection: selection)
      }
      return result(
        text,
        selection: NSRange(
          location: character.location,
          length: NSMaxRange(selection) - character.location
        )
      )
    case .selectRight:
      guard let character = characterAfter(NSMaxRange(selection), in: text) else {
        return result(text, selection: selection)
      }
      return result(
        text,
        selection: NSRange(
          location: selection.location,
          length: NSMaxRange(character) - selection.location
        )
      )
    case .selectToLineStart:
      let start = lineStart(at: selection.location, in: text)
      return result(
        text,
        selection: NSRange(location: start, length: NSMaxRange(selection) - start)
      )
    case .selectToLineEnd:
      let end = lineEnd(at: NSMaxRange(selection), in: text)
      return result(
        text,
        selection: NSRange(location: selection.location, length: end - selection.location)
      )
    case .deleteBackward:
      let deletionRange: NSRange
      if selection.length > 0 {
        deletionRange = selection
      } else if let character = characterBefore(selection.location, in: text) {
        deletionRange = character
      } else {
        return result(text, selection: selection)
      }
      return ComposerTextState(
        text: text.replacingCharacters(in: deletionRange, with: ""),
        selection: NSRange(location: deletionRange.location, length: 0)
      )
    }
  }

  private static func result(_ text: NSString, selection: NSRange) -> ComposerTextState {
    ComposerTextState(text: text as String, selection: selection)
  }

  private static func normalized(_ range: NSRange, textLength: Int) -> NSRange {
    let location = max(0, min(range.location, textLength))
    let length = max(0, min(range.length, textLength - location))
    return NSRange(location: location, length: length)
  }

  private static func characterBefore(_ position: Int, in text: NSString) -> NSRange? {
    guard position > 0 else { return nil }
    return text.rangeOfComposedCharacterSequence(at: position - 1)
  }

  private static func characterAfter(_ position: Int, in text: NSString) -> NSRange? {
    guard position < text.length else { return nil }
    return text.rangeOfComposedCharacterSequence(at: position)
  }

  private static func lineStart(at position: Int, in text: NSString) -> Int {
    guard position > 0 else { return 0 }
    let newline = text.range(
      of: "\n",
      options: .backwards,
      range: NSRange(location: 0, length: position)
    )
    return newline.location == NSNotFound ? 0 : NSMaxRange(newline)
  }

  private static func lineEnd(at position: Int, in text: NSString) -> Int {
    guard position < text.length else { return text.length }
    let newline = text.range(
      of: "\n",
      range: NSRange(location: position, length: text.length - position)
    )
    return newline.location == NSNotFound ? text.length : newline.location
  }
}
