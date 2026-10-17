package vt

import "unicode"

/// How many cells a code point takes: 0 for a combining mark or a
/// format character, 2 where its East_Asian_Width is W or F (ideographs,
/// Hangul, fullwidth forms, emoji shown as emoji), else 1. Ambiguous (A)
/// characters take one, as terminals outside East Asian locales set them.
public func CellWidth(_ cp: uint32) -> int {
    if cp < 0x300 { return 1 }
    if cp == 0x200B || cp == 0x200C || cp == 0x200D || cp == 0x2060 || cp == 0xFEFF { return 0 }
    if cp >= 0xFE00 && cp <= 0xFE0F { return 0 }
    if unicode.IsWide(cp) { return 2 }
    return zeroWidth(cp) ? 0 : 1
}

func zeroWidth(_ cp: uint32) -> bool {
    switch unicode.Category(cp) {
    case .nonspacingMark, .enclosingMark, .format: return true
    default: return false
    }
}
