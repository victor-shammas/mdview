import Foundation

enum ViewFont: String, CaseIterable, Equatable {
    case system = "System Sans"
    case serif = "System Serif"
    case georgia = "Georgia"
    case palatino = "Palatino"
    case charter = "Charter"

    var css: String {
        switch self {
        case .system:  return "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif"
        case .serif:   return "ui-serif, 'New York', Georgia, serif"
        case .georgia: return "Georgia, 'Times New Roman', serif"
        case .palatino: return "Palatino, 'Palatino Linotype', 'Book Antiqua', serif"
        case .charter: return "Charter, 'Bitstream Charter', Georgia, serif"
        }
    }
}

enum Appearance: String, Equatable {
    case auto, light, dark
}

enum TextAlignment: String, Equatable {
    case left, justify

    var css: String {
        switch self {
        case .left:    return "left"
        case .justify: return "justify"
        }
    }
}
