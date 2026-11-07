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

    /// Picture inside the AI chat ("like a message"): 400x100 px at the bottom of
    /// the lens (two 200x100 tiles, which the G2 code tiles itself), under the
    /// newest chat lines. Source: tile limit above; 100 px ≈ 3.5 text lines.
    static let chatPictureWidthPx: Int = 400
    static let chatPictureHeightPx: Int = 100
    static let chatPictureY: Int = lensHeightPx - chatPictureHeightPx

    /// Chat lines that fit above that picture (188 px / 28.8 px per line).
    static let chatLinesAbovePicture: Int = 6

    /// Navigation map: the biggest picture the glasses take (4 tiles = 400x200 px,
    /// see imageTile*), centered at the top; the directions go in two lines under it.
    static let navMapWidthPx: Int = imageTileWidthPx * imageTilesAcross
    static let navMapHeightPx: Int = imageTileHeightPx * imageTilesDown
    static let navMapX: Int = (lensWidthPx - navMapWidthPx) / 2
    static let navTextY: Int = navMapHeightPx + 4
    /// Lines under the map (84 px; one firmware line needs 40 px, per G2.minTextContainerHeight).
    static let navTextLines: Int = 2

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

    /// Listening after "Neo" (ListeningWindow): closes after this much silence
    /// (after "Neo" or an instant action), or this long without a response after
    /// an answer appears; paused while the user talks. Source: user's choice.
    static let listenSilenceSeconds: Double = 5
    static let listenAfterReplySeconds: Double = 10
    /// The "Yes?" indicator stays up at most this long (the window normally closes first).
    static let listenIndicatorSeconds: Double = 120

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

    /// Phone compass updates only after turning this many degrees (saves redraws;
    /// the arrow has 45° steps). Source: design choice.
    static let navHeadingFilterDegrees: Double = 5

    /// Map: meters from the user to the map's side edge (400 px wide -> 1 px/m),
    /// where the user sits (fraction of the height from the top), and how often
    /// it is redrawn. Source: design choice (about two city blocks each way).
    static let navMiniMapRadiusMeters: Double = 200
    static let navMiniMapUserYFraction: CGFloat = 0.62
    static let navMiniMapRefreshSeconds: Double = 2

    /// Apple Maps street background: this many times the map's size (so it can be
    /// reused while walking), refetched after moving this far from its center (the
    /// view reaches ~124 m north of the user; a 3x background has 300 m), and the
    /// tone-curve level below which its dark grey background becomes black.
    /// Source: design choice; MKMapSnapshotter is free in native apps.
    static let navBackgroundScale: CGFloat = 3
    static let navBackgroundRefetchMeters: Double = 150

    /// Street picture (StreetBackground): rendered at 2x for smooth edges;
    /// roads lit to this brightness (0-1, under the full-white route; names go
    /// brighter); at least this many route points must fall on the picture to
    /// measure the road gray; and the smallest road/land gray difference used
    /// (0-255), so a flat picture doesn't blow up. Source: design choice.
    static let navBackgroundRenderScale: CGFloat = 2
    static let navBackgroundRoadBrightness: CGFloat = 0.5
    static let navBackgroundMinRouteSamples: Int = 5
    static let navBackgroundMinContrast: Double = 12

    /// Map zoom: reach (meters from the middle to the side edge) stays within
    /// these, halving / doubling per "zoom in" / "zoom out"; "where is X" fits
    /// both points with this much extra margin. Source: design choice
    /// (50 m = a few buildings; 10 km = a city district).
    static let navZoomMinMeters: Double = 50
    static let navZoomMaxMeters: Double = 10_000
    static let navPlaceFitMargin: Double = 1.3

    /// Nearest-place search: try these radii in order until something is found,
    /// in meters (500, 1000, ... 5000), with results restricted to the area
    /// (MKLocalSearch regionPriority .required, iOS 18; without it Apple may
    /// return far-away matches). Source: user's choice of 500 m steps.
    static let navSearchRadiiMeters: [Double] = Array(stride(from: 500.0, through: 5000.0, by: 500.0))

    /// Map drawing: line width and marker radius, in pixels.
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

    /// Who the assistant is (shared by the iPhone AI and Claude). No double
    /// quotes or percent signs (sent to the PC bridge on a command line).
    static let aiRole: String = """
    You are Neo, the user's personal assistant; their smart glasses are only where \
    your answers appear, not a limit on what you do. Help with anything a good \
    assistant would: teach (languages such as Japanese, or any subject), explain, \
    quiz, practice conversation, give advice, or just chat. Never say you are only \
    a HUD assistant or can only give data. Answer exactly what was asked, the way a \
    person would, as short as possible. The [Context] line gives the current date, \
    time, place (time zone) and reply language; assume the user means their own \
    place and time unless they name another. Answer directly whatever you know yourself.
    """

    /// What each ability does, what the user sees, and what it costs, so the AI
    /// can judge when one helps (instead of fixed "call X when Y" rules).
    /// Shared by both AIs; each adds how to trigger them.
    static let aiAbilities: String = """
    YOUR ABILITIES (what each does and what the user sees): \
    1. Web search: looks up live or recent information and returns a short summary \
    and snippets to you. It uses one of the user's limited free monthly searches, so \
    use it only for things you can't know: weather, news, prices, opening hours, \
    scores, recent events, or facts you're unsure of. \
    2. Stock chart: draws a price line chart of a stock, index, currency pair or \
    crypto right in this chat, with the latest price and change. Free. \
    3. Chart: draws a bar chart (up to 8 values) or a line chart (more) in this chat \
    from numbers you provide. Only real numbers, from a search or the user. \
    4. Picture: finds a web photo and shows it in this chat under your answer. Uses \
    one search. Use when seeing it helps (how something looks, an animal, a place). \
    5. Save chat: saves this conversation (questions and answers) with a title; the \
    user reads it later in the Saved tab and can translate it there. \
    6. Listen: from now on the app saves the text of what people around the user say \
    (you can't hear it yourself) until told to stop; it appears in the Saved tab. \
    Use when the user wants to remember what someone says (a meeting, a shop clerk). \
    7. Directions (always with the map unless the user asks to hide it): finds the \
    nearest place matching what the user wants (Apple Maps) \
    and shows walking or driving turn-by-turn in the Nav tab, always starting with a \
    street map plus the next turn and distance. Only if the user asks for no map or \
    a clear screen, switch the view to minimal (one line at the top); map brings it back. \
    Show place: for where is / show me where / how far is, shows the nearest match and \
    the user together on the map with the walking distance, without turn-by-turn. \
    Zoom: zoom in / out the map (around the user in directions, around the place after show place). \
    For nearest, give just the kind of place (convenience store), not the word nearest. \
    8. Calculator: computes a formula exactly (+ - * / ^ ( ) %, phone-style percent) and \
    lists it in the Calc tab. Use it for ANY math instead of computing yourself: turn \
    everyday wording into a formula (a 15% tip on 4800 = 4800*15%, split 9600 among 3 = 9600/3). \
    9. Convert: exact unit conversion (length, weight, temperature, volume, speed, area \
    incl. tsubo) and currency at today's rate. Free. Lists it in the Calc tab. \
    THINGS THE USER DOES BY VOICE THEMSELVES (you can't do them; if asked, tell them \
    what to say, starting with Neo): switch tabs (next / back), scroll (up / down), \
    notes (Neo, note buy milk), reminders (Neo, remind me at 5 to call), plain math \
    straight to the Calc tab (Neo, 12 times 35, then Neo, plus 5), and in the Saved tab \
    open an item by number and say translate.
    """

    // MARK: - Claude on the PC

    /// Wait for the PC bridge, in seconds. Must exceed the bridge's own
    /// 120 s Claude timeout (PCBridge/bridge.ps1) so its error message arrives.
    static let claudeBridgeTimeoutSeconds: Double = 130

    /// Appended to Claude Code's system prompt on the PC. No double quotes or
    /// percent signs (the bridge strips them from the command line).
    static let claudeInstructions: String = aiPersonality + " " + aiNumbersRule + " " + aiRole
        + " Keep answers under 200 characters, plain text, no markdown or lists. " + aiAbilities + " " + """
    HOW TO USE AN ABILITY: end your reply with ONE action line and the app does it. \
    Web search: use your own web search tool. \
    Stock chart: STOCK: <name as Yahoo Finance lists it> | <day, week, month, year or fiveYears>. \
    Chart: CHART: <title> | <unit> | <label>=<number>; <label>=<number>. \
    Picture: IMAGE: <2-5 English search words>. \
    Save chat: SAVE: <short title>. \
    Listen: LISTEN: <short title>, and LISTEN_STOP to end it. \
    Directions: DIRECTIONS: <place as a map search> | <walking or driving>, DIRECTIONS_STOP \
    to end them, DIRECTIONS_VIEW: <map, minimal, zoomin or zoomout> for the view. \
    Show place: PLACE: <place as a map search>. \
    Calculator: CALC: <formula>, and the exact result is added to your answer, so don't \
    compute it yourself. Convert: CONVERT: <value> | <from unit or currency> | <to>.
    """

    // MARK: - On-device AI

    /// Search text handed back to the on-device AI from its searchWeb tool, in
    /// characters (its context is ~4k tokens, shared with instructions, tool
    /// schemas, and the chat). Source: Apple Foundation Models docs (context size).
    static let aiToolResultMaxChars: Int = 1500

    /// System instructions for the on-device model. Each question starts with a
    /// [Context: ...] line (date, time, time zone, reply language).
    static let aiInstructions: String = aiPersonality + " " + aiNumbersRule + " " + aiRole
        + " Keep answers under 120 characters, plain text, no markdown or lists. " + aiAbilities + " " + """
    HOW TO USE AN ABILITY: call its tool. Web search = searchWeb, stock chart = \
    stockChart, chart = drawChart, picture = showPicture, save chat = saveChat, \
    listen = startListening / stopListening, directions = startDirections / \
    stopDirections / directionsView (also zoom), show place = showPlace, calculator = calculate, convert = convert. After a tool, \
    reply with one short sentence.
    """
}
