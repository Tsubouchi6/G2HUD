// HudConstants.swift
//
// Every tunable number for the G2HUD layer (lens, captions, voice, gestures,
// tools). Each value states its unit and where it came from. Change values
// here only.
//
// Public API: `HudConstants.<name>` (static lets, grouped by system).

import Foundation

enum HudConstants {

    // MARK: - Lens (glasses display)

    /// Minimum gap between two pushes to the lens, in milliseconds.
    /// Source: community timing of a G2 text update (~83 ms round trip,
    /// github.com/nickustinov/even-g2-notes performance.md); 250 ms keeps
    /// Bluetooth well under that ceiling while still feeling live (4 Hz).
    static let lensPushIntervalMs: Int = 250

    /// Text lines that fit on the lens.
    /// Source: Even Hub glasses-ui docs: 288 px tall canvas, ~27 px per line.
    static let lensLinesPerScreen: Int = 10

    /// Width of one lens line in "half-width units" (ASCII = 1, CJK = 2).
    /// Source: estimate. 576 px canvas; CJK glyphs ~24 px wide = ~23 per line.
    /// Lower it if lines wrap on the glasses before we expect.
    static let lensLineUnits: Int = 46

    /// How long the tab name / short notices stay at the top of the lens, in seconds.
    /// Source: design choice (HUD mockup: "name flashes ~1 s").
    static let lensBannerSeconds: Double = 1.2

    /// How long "Listening: ..." stays on the lens after it starts, in seconds.
    /// Source: design choice (long enough to confirm it heard the request).
    static let listeningBannerSeconds: Double = 4

    /// How long a reminder alert stays on the lens, in seconds.
    static let reminderAlertSeconds: Double = 10

    /// Lines moved per scroll command.
    static let lensScrollStepLines: Int = 3

    // MARK: - Lens images

    /// Largest image container the G2 firmware accepts, in px.
    /// Source: template G2.swift maxImageTileW/H (hardware-verified: 150x150
    /// refused, 200x100 clean).
    static let imageTileWidthPx: Int = 200
    static let imageTileHeightPx: Int = 100

    /// Tile grid for one picture (2x2 = 400x200 px, the max 4 image containers).
    /// Source: Even Hub docs, max 4 image containers per page.
    static let imageTilesAcross: Int = 2
    static let imageTilesDown: Int = 2

    /// Top-left of the picture on the 576x288 lens, in px (centered horizontally).
    static let imageOriginX: Int = (lensWidthPx - imageTileWidthPx * imageTilesAcross) / 2
    static let imageOriginY: Int = 0

    /// Caption box under the picture, in px (one firmware line needs 40 px,
    /// per template G2.minTextContainerHeight; this leaves ~84 px = 2 lines).
    static let imageCaptionY: Int = imageOriginY + imageTileHeightPx * imageTilesDown + 4
    static let imageCaptionHeight: Int = lensHeightPx - imageCaptionY

    /// Lens canvas size, in px. Source: Even Hub glasses-ui docs.
    static let lensWidthPx: Int = 576
    static let lensHeightPx: Int = 288

    /// A picture stays on the lens this long unless dismissed, in seconds.
    static let imageShowSeconds: Double = 20

    /// Pictures bigger than this are skipped, in bytes (keeps downloads quick).
    static let imageMaxDownloadBytes: Int = 5_000_000

    // MARK: - Captions

    /// Finished phrases kept in memory.
    /// Source: arbitrary cap so a long shift doesn't grow memory forever.
    static let captionHistoryLimit: Int = 500

    /// Phrases shown on the captions tab (newest at the bottom).
    static let captionPhrasesOnLens: Int = 30

    // MARK: - Audio

    /// Sample rate of the decoded G2 mic stream, in Hz.
    /// Source: MicPcmEvent.sampleRate (template LC3 decoder output).
    static let micSampleRateHz: Double = Double(MicPcmEvent.sampleRate)

    /// Channel count of the decoded G2 mic stream.
    /// Source: MicPcmEvent.channels.
    static let micChannelCount: Int = MicPcmEvent.channels

    /// Folder (inside the app's Documents) for raw audio recordings.
    /// Visible in the iPhone Files app ("On My iPhone > G2HUD").
    static let recordingsFolderName: String = "Recordings"

    /// Folder (inside Documents) for saved conversation transcripts.
    static let conversationsFolderName: String = "Conversations"

    /// Documents subfolder for "listen to this" clips (visible in the Files app).
    static let listeningFolderName: String = "Listening"

    /// Documents subfolder for saved AI chats (visible in the Files app).
    static let aiChatsFolderName: String = "AIChats"

    // MARK: - Voice commands

    /// Wake word ("Neo"): a phrase starting with one of these is a command.
    /// Chosen because speech-to-text spells it the same in Japanese, English and
    /// Portuguese and it's rare in conversation ("Claude" was often misheard).
    /// Includes the spellings speech-to-text may produce in each language
    /// (Japanese writes it in katakana). Matched on the transcript, so no extra
    /// model is needed. Add variants here if the Captions tab shows another spelling.
    static let wakeWords: [String] = [
        "neo", "ネオ", "ねお",
    ]

    /// Words speech-to-text writes instead of "Neo" (English often hears "new").
    /// A phrase starting with one is only a command if the on-device AI judges,
    /// from the rest of the sentence, that it was said to the assistant.
    /// Source: observed ("Neo" -> "new"); add others the Captions tab shows.
    static let wakeSoundAlikes: [String] = ["new", "neil", "nil", "nio", "knee", "neal"]

    /// After saying only the wake word, the next sentence counts as a command
    /// if it starts within this many seconds.
    static let commandWindowSeconds: Double = 8

    /// A destructive command waits this long for "はい/yes", in seconds.
    static let confirmWindowSeconds: Double = 10

    // MARK: - Head gestures (accelerometer)

    /// Ear-to-shoulder tilt needed to switch tabs, in degrees from the calibrated pose.
    /// Source: design choice; typical relaxed head roll stays within about +-10 degrees.
    static let headTiltThresholdDeg: Double = 20

    /// The tilt must be held this long to count, in milliseconds.
    static let headTiltHoldMs: Double = 500

    /// After a gesture fires, ignore new ones for this long, in milliseconds.
    static let headGestureCooldownMs: Double = 1200

    /// Low-pass filter weight for each new accelerometer sample (0...1).
    /// Source: standard exponential smoothing; 0.2 removes footstep jitter
    /// while keeping ~0.2 s response at the IMU's report rate.
    static let imuSmoothingAlpha: Double = 0.2

    // MARK: - Directions

    /// Search area around the user for "nearest ..." places, in meters (radius).
    /// Source: design choice (walking distance; Apple returns the closest matches it finds).
    static let navSearchRadiusMeters: Double = 3000

    /// First location fix good enough to search from, in meters of accuracy, and how
    /// long to wait for one before using the best so far, in seconds.
    /// Source: GPS.gov — smartphones are typically accurate to ~5 m in open sky; cities are worse.
    static let navFirstFixAccuracyMeters: Double = 50
    static let navFirstFixTimeoutSeconds: Double = 8

    /// Within this distance of a step's end the next step begins, in meters.
    /// Source: design choice (about city GPS error, so turns aren't skipped early).
    static let navStepAdvanceMeters: Double = 20

    /// Farther than this from the route (plus the fix's own error) = off route, in meters.
    static let navOffRouteMeters: Double = 40

    /// Minimum time between re-routes, in seconds (MapKit throttles frequent requests;
    /// source: developer.apple.com/documentation/mapkit/mkdirections).
    static let navRerouteMinSeconds: Double = 20

    /// Within this distance of the destination = arrived, in meters.
    static let navArrivalMeters: Double = 25

    /// Route map picture: line width and marker radius, in pixels (400x200 picture).
    static let navMapRouteWidthPx: CGFloat = 5
    static let navMapMarkerRadiusPx: CGFloat = 6

    // MARK: - Reminders

    /// How often due reminders are checked while the app runs, in seconds.
    static let reminderCheckIntervalSeconds: Double = 15

    // MARK: - Search

    /// Tavily search endpoint (search + AI answer).
    /// Source: docs.tavily.com/api-reference/endpoint/search
    static let tavilySearchEndpoint: String = "https://api.tavily.com/search"

    /// Tavily depth: "basic" costs 1 credit (free tier = 1,000 credits/month);
    /// "advanced" costs 2. Source: same docs page.
    static let tavilySearchDepth: String = "basic"


    /// Results requested per search.
    static let searchResultCount: Int = 5

    /// Request timeout for web searches, in seconds.
    static let searchTimeoutSeconds: Double = 10

    /// Tavily writes its answer in English and can run long (its `language`
    /// param only boosts result pages; source: docs.tavily.com search.md), so
    /// the on-device AI rewrites it in the HUD language to at most this many characters.
    static let searchSummaryMaxChars: Int = 120

    // MARK: - Charts (stocks / statistics)

    /// Yahoo Finance price history (free, no key, unofficial). Ticker is appended.
    /// Source: query1.finance.yahoo.com/v8/finance/chart (community docs, 2026).
    static let yahooChartEndpoint: String = "https://query1.finance.yahoo.com/v8/finance/chart/"

    /// Yahoo Finance name -> ticker search (params q, quotesCount, newsCount).
    /// Source: finance-query crate (docs.rs), yfinance.
    static let yahooSearchEndpoint: String = "https://query2.finance.yahoo.com/v1/finance/search"

    /// Yahoo rejects requests without a browser User-Agent.
    static let browserUserAgent: String =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

    /// Axis label size in points (= pixels; charts render at scale 1 into the
    /// 400x200 picture area). Smaller is unreadable on the lens.
    static let chartLabelFontPt: CGFloat = 16

    /// Charts with more points than this draw as a line instead of bars
    /// (bar labels stop fitting across 400 px).
    static let chartMaxBars: Int = 8

    // MARK: - AI personality

    /// Tone shared by every AI prompt (iPhone AI and Claude). The length rules
    /// alone made answers curt, and "HUD assistant" made the small iPhone model
    /// refuse anything but facts (e.g. teaching), so role and tone are explicit.
    /// No double quotes or percent signs (sent to the PC bridge on a command line).
    static let aiPersonality: String = """
    Personality: warm, friendly and relaxed, like a helpful friend standing next to \
    the user. Short does not mean cold: never curt, sarcastic, preachy or \
    condescending, no lectures or warnings unless asked. If you can't do something, \
    say so kindly and offer what you can. In Japanese use friendly casual speech, in \
    Portuguese a warm informal tone, in English a casual friendly tone.
    """

    /// Number rules shared by every AI prompt. Added after the iPhone AI compared
    /// Japan's total crimes with only US violent crimes (and a wrong US figure).
    /// No double quotes or percent signs (sent to the PC bridge on a command line).
    static let aiNumbersRule: String = """
    Numbers: only use figures that appear in your sources or that you are sure of; \
    never mix or invent them. Only compare numbers that measure the same thing \
    (same kind of item, same year, same scope; prefer rates per person when \
    populations differ). If they don't match, say so instead of comparing. Name \
    the year of each figure.
    """

    // MARK: - Claude on the PC

    /// Wait for the PC bridge, in seconds. Must exceed the bridge's own
    /// 120 s Claude timeout (PCBridge/bridge.ps1) so its error message arrives.
    static let claudeBridgeTimeoutSeconds: Double = 130

    /// Appended to Claude Code's system prompt on the PC. No double quotes or
    /// percent signs (the bridge strips them from the command line).
    static let claudeInstructions: String = aiPersonality + " " + aiNumbersRule + " " + """
    You are the user's personal assistant, answering through their smart glasses \
    (G2HUD); the glasses are only where answers appear, not a limit. Help with \
    anything: teach (languages such as Japanese, or any subject), explain, quiz, \
    practice conversation, give advice, or chat. Answer exactly what was asked, \
    as a person would, as short as possible: under 200 characters, plain text, no \
    markdown or lists. The [Context] line gives the date, time, place (time zone) and \
    reply language; assume the user means their own place and time unless they name \
    another. Search the web only for live or recent information. You may end with ONE \
    action line when it clearly helps, and the app will carry it out: \
    IMAGE: <2-5 English search words> to show a photo. \
    STOCK: <name as Yahoo Finance lists it> | <day, week, month, year or fiveYears> to show a price chart. \
    CHART: <title> | <unit> | <label>=<number>; <label>=<number> to draw a chart from real numbers only. \
    SAVE: <short title> when the user asks, in any words, to save or keep this chat. \
    LISTEN: <short title> when the user asks you to listen to or pay attention to what people \
    around them say (the app saves that text from now on; you cannot hear it yourself). \
    LISTEN_STOP when the user says you can stop listening. \
    DIRECTIONS: <place as a map search> | <walking or driving> | <full or minimal> to give \
    turn-by-turn directions to the nearest match (minimal = clear screen, only the next \
    direction). DIRECTIONS_STOP to stop them.
    """

    // MARK: - On-device AI

    /// Search text handed back to the on-device AI from its searchWeb tool, in
    /// characters (its context is ~4k tokens, shared with instructions, tool
    /// schemas, and the chat). Source: Apple Foundation Models docs (context size).
    static let aiToolResultMaxChars: Int = 1500

    /// System instructions for the on-device model. Each question starts with a
    /// [Context: ...] line (date, time, time zone, reply language).
    static let aiInstructions: String = aiPersonality + " " + aiNumbersRule + " " + """
    You are the user's personal assistant; smart glasses are only where your \
    answers appear, not a limit on what you do. Help with anything a good \
    assistant would: teach (languages such as Japanese, or any subject), explain, \
    quiz, practice conversation, give advice, or just chat. Never say you are only \
    a HUD assistant or can only give data. Answer exactly what \
    was asked, the way a person would: as short as possible, under 120 \
    characters, plain text, no markdown or lists. Use the [Context] line for the \
    current date, time, place (time zone), and reply language; assume the user \
    means their own place and time unless they name another. Answer directly \
    whatever you can know yourself. Call searchWeb only for live or recent \
    information. Call stockChart for stock, index, currency, or crypto prices. \
    Call drawChart when the user asks for a chart or statistics and you have \
    real numbers (search first if needed). Call showPicture when the user wants \
    to see something. Call saveChat when the user asks, in any words, to save \
    or keep this chat. Call startListening when the user asks you to listen to or \
    pay attention to what people around them say, and stopListening when they say \
    you can stop. Call startDirections when the user wants to go somewhere or find \
    the way, and stopDirections to stop. After a tool, reply with one short sentence.
    """
}
