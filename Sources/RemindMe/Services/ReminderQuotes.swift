import Foundation

/// A short line under a reminder's title on its popup. Matched to what the
/// reminder is about when the title gives it away, otherwise a general one.
enum ReminderQuotes {
    private static let topics: [(words: [String], quotes: [String])] = [
        (["water", "drink", "hydrate", "sip"], [
            "Stay hydrated, stay sharp.",
            "Water first, edits second.",
            "One glass closer to a clear head.",
            "Your brain is mostly water. Top it up.",
        ]),
        (["stretch", "walk", "move", "stand", "exercise", "yoga", "posture", "sit"], [
            "Move a little, feel a lot better.",
            "Your back will thank you.",
            "Stand up. Shake it out.",
            "Motion is lotion.",
        ]),
        (["eye", "eyes", "blink", "screen", "look"], [
            "Look far away for 20 seconds.",
            "Blink. Breathe. Back to it.",
            "Rest your eyes, sharpen your cut.",
        ]),
        (["breathe", "breath", "rest", "break", "relax", "meditate"], [
            "Breathe in. Slow down.",
            "Pause is part of the work.",
            "A calm mind makes better choices.",
        ]),
        (["eat", "lunch", "dinner", "breakfast", "snack", "food", "meal"], [
            "Fuel up. The timeline can wait.",
            "Good food, good mood.",
        ]),
        (["call", "message", "text", "email", "reply", "mom", "dad"], [
            "A quick hello goes a long way.",
            "Do it now, forget it after.",
        ]),
        (["sleep", "bed", "nap"], [
            "Tomorrow's you needs this.",
            "Close the laptop. Seriously.",
        ]),
    ]

    private static let general = [
        "Small steps, every day.",
        "Future you says thanks.",
        "Done is better than perfect.",
        "Tiny habits, big change.",
        "A little now beats a lot later.",
        "Consistency beats intensity.",
        "You've got this.",
        "Be kind to yourself today.",
    ]

    /// The lines that fit this title (its topic's, or the general ones).
    static func choices(for title: String) -> [String] {
        let words = Set(title.lowercased().split { !$0.isLetter }.map(String.init))
        for topic in topics where topic.words.contains(where: { word in
            words.contains(word) || words.contains(word + "s")
        }) {
            return topic.quotes
        }
        return general
    }

    /// One line for this title; `pick` chooses which (any number works).
    static func quote(for title: String, pick: Int) -> String {
        let lines = choices(for: title)
        return lines[((pick % lines.count) + lines.count) % lines.count]
    }
}
