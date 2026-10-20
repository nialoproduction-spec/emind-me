import Foundation

/// Short lines shown with reminders, habits and goals, matched to what the
/// title is about ("Drink water" gets a water line). Kept short enough for
/// one line on the habit card. No dashes, no lectures.
enum ReminderQuotes {
    struct Topic {
        let words: [String]
        let quotes: [String]
    }

    static let topics: [Topic] = [
        Topic(words: ["water", "drink", "hydrate", "hydration", "sip", "bottle", "glass"], quotes: [
            "Stay hydrated, stay sharp.",
            "Water first, edits second.",
            "One glass closer to a clear head.",
            "Your brain is mostly water. Top it up.",
            "Sip, sip, hooray.",
            "Plants need water. So do you.",
            "Hydration is a personality trait now.",
            "Your bottle misses you.",
            "Thirsty brains make sloppy cuts.",
            "A glass now saves a headache later.",
            "Drink up, buttercup.",
            "Be like a fish. Stay in water.",
            "Water: the original energy drink.",
            "Your kidneys say thank you.",
            "Refill the tank before the light comes on.",
            "Glug glug, you've got this.",
            "Clear water, clear mind.",
            "Ten seconds. One glass. Go.",
            "Even the timeline needs a rest. Drink.",
            "Dehydration is not an aesthetic.",
        ]),
        Topic(words: ["stretch", "walk", "move", "stand", "exercise", "yoga", "posture", "sit", "gym", "run",
                      "workout", "steps", "pushup", "pushups", "squat", "squats", "back", "neck", "shoulders"], quotes: [
            "Move a little, feel a lot better.",
            "Your back will thank you.",
            "Stand up. Shake it out.",
            "Motion is lotion.",
            "Unclench your shoulders.",
            "Sit up like you mean it.",
            "Roll your neck. Slowly.",
            "A short walk is a big reset.",
            "Your spine is not a question mark.",
            "Chairs are lovely. Leave one.",
            "Ten squats. You'll survive.",
            "Stretch like a cat after a nap.",
            "Blood flow is good for ideas.",
            "Get up before your legs forget how.",
            "Walk it off, champ.",
            "Tiny workout, big mood.",
            "Your body is not a background layer.",
            "Reach for the ceiling. Then the floor.",
            "Shake out your hands. Editors need wrists.",
            "Five minutes moving beats an hour stiff.",
        ]),
        Topic(words: ["eye", "eyes", "blink", "screen", "look", "glasses", "vision"], quotes: [
            "Look far away for 20 seconds.",
            "Blink. Breathe. Back to it.",
            "Rest your eyes, sharpen your cut.",
            "Find the farthest thing you can see.",
            "Your eyes are not on a render queue.",
            "Close your eyes. Count to ten.",
            "Look out the window like a movie character.",
            "Blink ten times. Dramatically.",
            "Screens can wait. Eyes can't.",
            "Give your eyes a little holiday.",
        ]),
        Topic(words: ["breathe", "breath", "breathing", "rest", "break", "relax", "meditate", "calm", "pause", "chill"], quotes: [
            "Breathe in. Slow down.",
            "Pause is part of the work.",
            "A calm mind makes better choices.",
            "In for four, out for six.",
            "Nothing is on fire. Breathe.",
            "Rest is productive. Promise.",
            "Drop your shoulders. Unclench your jaw.",
            "Slow is smooth. Smooth is fast.",
            "The deadline can hear you breathe.",
            "One long breath. That's the whole task.",
            "You're allowed to pause.",
            "Recharge like you mean it.",
        ]),
        Topic(words: ["eat", "lunch", "dinner", "breakfast", "snack", "food", "meal", "cook", "fruit", "tea", "coffee", "khana"], quotes: [
            "Fuel up. The timeline can wait.",
            "Good food, good mood.",
            "Hungry editors cut everything short.",
            "Eat like you like yourself.",
            "Snack break is a valid break.",
            "Food first, feedback later.",
            "No one makes great work on an empty stomach.",
            "Your stomach filed a complaint.",
            "Real food. Not just coffee.",
            "Chew slowly. You earned it.",
            "Tea time is a state of mind.",
            "Coffee is not a meal. Sorry.",
        ]),
        Topic(words: ["call", "message", "text", "email", "reply", "mom", "dad", "mum", "friend", "family", "client",
                      "whatsapp", "phone", "meeting", "ring"], quotes: [
            "A quick hello goes a long way.",
            "Do it now, forget it after.",
            "Two minutes. Hit send.",
            "Someone will be glad you called.",
            "Inbox zero is a myth. Reply anyway.",
            "Clients love a fast reply.",
            "Say the thing. Kindly.",
            "Your mom wants to hear from you.",
            "Short message, big relief.",
            "The longer you wait, the weirder it gets.",
            "Hit reply before it hits you.",
            "People remember who called back.",
        ]),
        Topic(words: ["sleep", "bed", "nap", "night", "bedtime"], quotes: [
            "Tomorrow's you needs this.",
            "Close the laptop. Seriously.",
            "Sleep is the best plugin.",
            "Renders finish. You should too.",
            "Dream in 4K.",
            "Nothing good happens after 2 AM in Premiere.",
            "Bed is calling. Pick up.",
            "Rested eyes catch the jump cuts.",
            "Good night, timeline.",
            "Save, close, sleep.",
        ]),
        Topic(words: ["edit", "editing", "export", "render", "grade", "grading", "color", "colour", "timeline", "footage",
                      "cut", "project", "wedding", "video", "clip", "clips", "sync", "upload", "backup", "deliver",
                      "premiere", "davinci", "resolve", "teaser", "highlight", "reel", "film", "sound", "audio", "music"], quotes: [
            "Save first. Always save first.",
            "Back it up before it backs out.",
            "Export it, then exhale.",
            "Kill your darlings. Keep the best take.",
            "The couple will cry. Good cry.",
            "Cut on the beat, live off the beat.",
            "Great edits are mostly deleted footage.",
            "Two backups is one backup.",
            "Color grade your mood too.",
            "Done is better than perfect. Deliver it.",
            "Trust the J cut.",
            "Music first, then the magic.",
            "Every frame is a promise.",
            "Name your files like future you is watching.",
            "Render bar moving? Go stretch.",
            "Less zoom, more story.",
            "If it feels long, it is long.",
            "Watch it once with fresh eyes.",
            "Upload now, panic never.",
            "The best transition is a good cut.",
            "Sync the audio, then your soul.",
            "Your client can't see the timeline. Relax.",
        ]),
        Topic(words: ["study", "read", "learn", "german", "deutsch", "practice", "lesson", "book", "course", "homework",
                      "revise", "ausbildung", "class", "vocab", "language"], quotes: [
            "Ten minutes a day beats ten hours once.",
            "Übung macht den Meister.",
            "One page is still progress.",
            "Your future self is studying with you.",
            "Small reps, big brain.",
            "Learn it like you'll teach it.",
            "Confusion is the start of learning.",
            "Read one paragraph. Then another.",
            "Langsam, aber sicher.",
            "Every word learned is a door opened.",
            "Practice now, flex later.",
            "Brains grow when you show up.",
        ]),
        Topic(words: ["clean", "laundry", "dishes", "tidy", "trash", "room", "plants", "vacuum", "desk", "organize", "chores"], quotes: [
            "Clean desk, clear head.",
            "Five minute tidy. Go.",
            "Future you loves clean dishes.",
            "Small mess now, no mess later.",
            "Put on music. Clean like a movie montage.",
            "Laundry waits for no one.",
            "One thing back in its place.",
            "Your plants are waiting.",
            "Tidy space, tidy timeline.",
            "Do the boring thing. Feel amazing after.",
        ]),
        Topic(words: ["pay", "bill", "bills", "invoice", "bank", "money", "rent", "budget", "tax", "taxes", "salary", "payment"], quotes: [
            "Pay it now, forget it forever.",
            "Send the invoice. You earned it.",
            "Late fees are nobody's friend.",
            "Money talks. Tell it where to go.",
            "Track it today, thank yourself later.",
            "Ten minutes of numbers, a month of calm.",
            "Get paid. Then celebrate.",
            "Boring tasks, beautiful bank balance.",
        ]),
        Topic(words: ["medicine", "meds", "pill", "pills", "vitamin", "vitamins", "supplement", "dentist", "doctor", "skincare"], quotes: [
            "Small thing, big help.",
            "Take care of the person doing the work.",
            "Future you says thanks.",
            "Quick, easy, done.",
            "Health first. Then everything else.",
            "A tiny habit that pays off.",
        ]),
    ]

    /// For reminders that match no topic.
    static let general = [
        "Small steps, every day.",
        "Future you says thanks.",
        "Done is better than perfect.",
        "Tiny habits, big change.",
        "A little now beats a lot later.",
        "Consistency beats intensity.",
        "You've got this.",
        "Be kind to yourself today.",
        "Do it now, enjoy it later.",
        "Two minutes. That's all it takes.",
        "Start ugly. Fix it later.",
        "Momentum loves a first step.",
        "Easy wins still count.",
        "You said you'd do this. Hero move.",
        "Your reminder believes in you.",
        "Knock it out, then nap.",
        "Not tomorrow. Now.",
        "One thing at a time.",
        "Progress, not perfection.",
        "Do the thing, feel the glow.",
        "Nobody regrets doing it.",
        "Plot twist: you actually do it.",
        "Main character energy. Go.",
        "Your to-do list is watching.",
        "Quick! Before you forget again.",
    ]

    /// Under a habit's card: about showing up again and again.
    static let habit = [
        "Same time tomorrow?",
        "Streaks are built one tap at a time.",
        "Show up. That's the habit.",
        "You're becoming someone who does this.",
        "Don't break the chain.",
        "Repetition is the secret sauce.",
        "Habit loading… keep going.",
        "Small and daily wins every time.",
        "Missed one? Never miss two.",
        "Boring on purpose. That's the trick.",
        "Every Done is a vote for you.",
        "You don't need motivation. Just the tap.",
    ]

    /// For the evening goal check-in.
    static let goal = [
        "Big goals, small daily steps.",
        "Did today move you closer?",
        "Honest answers make real progress.",
        "Not today is fine. Tomorrow counts too.",
        "Aim high, start small.",
        "Goals love consistency.",
        "You're closer than yesterday.",
        "Dream big. Check in daily.",
        "One honest tick at a time.",
        "Slow progress is still progress.",
        "The goal is the direction, not the finish line.",
        "Win the day, win the goal.",
        "Keep the promise you made to yourself.",
        "Little by little, a little becomes a lot.",
    ]

    /// What a reminder says as it's dismissed by hovering over it.
    static let lastWords = [
        "Fine. I'll go.",
        "Tell my family I loved them.",
        "Ignored again…",
        "I was only trying to help!",
        "Nooooo!",
        "Remember me.",
        "Is this how it ends?",
        "Avenge me, future you.",
        "I'll be back. Every 40 minutes.",
        "Rude. But fair.",
        "My only purpose…",
        "Goodbye, cruel desktop.",
        "See you in the next reminder.",
        "I never even got to remind you.",
        "Tragic. Truly tragic.",
        "Not like this…",
        "x_x",
        "Delete me then. See if I care.",
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
        line(from: choices(for: title), pick: pick)
    }

    /// A line for a habit: its topic's when it has one, otherwise a habit one.
    static func habitQuote(for title: String, pick: Int) -> String {
        let topical = choices(for: title)
        return line(from: topical == general ? habit : topical + habit, pick: pick)
    }

    static func line(from lines: [String], pick: Int) -> String {
        lines[((pick % lines.count) + lines.count) % lines.count]
    }

    static var total: Int {
        topics.reduce(0) { $0 + $1.quotes.count } + general.count + habit.count + goal.count + lastWords.count
    }
}
