# YouTube feature catalog: every element on the platform in 2026

YouTube's desktop website has evolved into a sprawling application with hundreds of interactive elements, controls, and features across **25+ distinct surfaces**. This catalog documents every known UI component, control, and feature as of April 2026—including the major Material Design 3 redesign shipped October 2025, the January 2026 search filter overhaul, and the April 10, 2026 pricing restructure. It also covers the third-party enhancement ecosystem and macOS-specific considerations for building a native client.

## GlassTube implementation notes (2026-04-12)

- This document is a full platform catalog. GlassTube intentionally implements a focused subset.
- Current app behavior differs from YouTube web in these areas:
  - No voice-search microphone in the search bar.
  - Home category/filter chips are removed.
  - Search bar presentation is intentionally simplified to a single surface in the toolbar.
  - Shorts and notifications surfaces are intentionally removed from active navigation.
  - Sidebar scope is focused on Home, Subscriptions, and Library sub-items (Playlists, Your Videos, Watch Later, Liked Videos, Downloads).
  - Videos open in internal in-app watch tabs instead of modal sheets.
  - SponsorBlock segments are shown on the timeline and can auto-skip supported categories.
  - Related videos sidebar is populated from Innertube related-video parsing.
  - Google sign-in requires user-provided OAuth credentials (TVs and Limited Input client) configured in Settings or account-popover quick setup.

---

## 1. Header bar and global navigation

The persistent top bar contains YouTube's primary navigation and account controls.

**Left cluster:**
- **Hamburger menu (☰)** — toggles the left sidebar between expanded and collapsed (mini) states
- **YouTube logo** — returns to homepage; region-specific suffixes appear for YouTube TV, Music, Kids

**Center: Search bar**
- Text input with placeholder "Search"
- **Autocomplete dropdown** showing trending searches, search history (removable per item), and predictive suggestions
- **Voice search button (microphone icon)** — opens voice recognition modal using Web Speech API
- **Search button (magnifying glass)** — submits query
- Keyboard shortcut: **/** (forward slash) focuses the search bar

**Right cluster:**
- **Create button (+)** — dropdown with: Upload video, Go live, Create a Short, Create post
- **Notifications bell (🔔)** — badge shows unread count; opens dropdown panel with all notification types (uploads, live streams, premieres, community posts, comments, mentions, milestones, recommendation digests); includes "Mark all as read" and link to notification settings
- **Profile avatar** — opens account dropdown menu

**Account dropdown menu items (in order):**
- Your channel
- YouTube Studio
- Switch account (lists all signed-in Google accounts)
- Sign out
- Purchases and memberships
- Your data in YouTube
- Appearance: Device theme / Dark theme / Light theme
- Language (full list of supported languages)
- Restricted Mode: On / Off toggle
- Location (country selector)
- Keyboard shortcuts (opens overlay, also accessible via **Shift+?**)
- Settings
- Help
- Send feedback

---

## 2. Left sidebar — collapsed and expanded states

**Mini sidebar (collapsed)** shows icon-only buttons for: Home, Shorts, Subscriptions, You.

**Expanded sidebar sections (top to bottom):**

**Primary navigation:**
- Home
- Shorts
- Subscriptions

**"You" section (personal library):**
- Your channel
- History
- Playlists
- Your videos
- Watch Later
- Liked videos
- Downloads (Premium users only)
- Your clips
- Your courses

**Subscriptions list:**
- Individual subscribed channel icons and names (collapsed behind "Show more" after ~7 channels)
- "All subscriptions" link at the bottom

**Explore section:**
- Trending (note: removed from some regions July 2025, replaced by topic-spread tracking)
- Shopping
- Music
- Movies & TV
- Live
- Gaming
- News
- Sports
- Courses
- Fashion & Beauty
- Podcasts

**More from YouTube:**
- YouTube Premium
- YouTube Studio
- YouTube Music
- YouTube Kids
- YouTube TV (US only)

**Footer links:**
- Settings, Report history, Help, Send feedback
- About, Press, Copyright, Contact us, Creators, Advertise, Developers, Terms, Privacy, Policy & Safety, How YouTube works, Test new features
- © 2026 Google LLC

---

## 3. Home feed — every component

The home feed is YouTube's primary discovery surface, powered by a satisfaction-weighted recommendation algorithm introduced in early 2025 that measures whether viewers felt time was well-spent, not just clicks and watch time.

**Filter chips (horizontal scrollable row at top):**
- "All" (default), then dynamically generated based on viewing history: Gaming, Music, Mixes, Live, News, Recently uploaded, Watched, New to you, Computer Science, Cooking, Sports, plus any topic YouTube infers from behavior
- Chips scroll horizontally with left/right arrows

**Video card anatomy (each recommendation):**
- **Thumbnail**: 16:9 aspect ratio with duration overlay badge (bottom-right, e.g., "12:34"), progress bar (red, for partially watched videos), "LIVE" red badge for active streams, "UPCOMING" badge for scheduled premieres, "NEW" badge for recent uploads, "SHORTS" badge overlay for short-form content
- **Video title**: two-line truncated text
- **Channel avatar**: circular profile image (links to channel page)
- **Channel name** with verification badge (gray checkmark or music note for Official Artist Channels)
- **Metadata line**: view count ("1.2M views") · relative upload time ("3 days ago")
- **Three-dot menu (⋮)** per card: Not interested, Don't recommend channel, Add to queue, Save to Watch Later, Save to playlist, Share, Report

**Shelf types on home feed:**
- Standard video recommendation grid
- **Shorts shelf** — horizontal row of vertical Short thumbnails
- **Breaking News shelf** — news cluster with source labels
- **Trending shelf** (where available)
- **"New to you"** section — content from channels the user hasn't watched
- **Ad/promoted cards** — labeled "Ad" with yellow badge, identical card layout otherwise
- **Movie/show shelves** — purchase/rent options with pricing
- **Mix playlist cards** — auto-generated playlists (e.g., "My Mix", "Discover Mix")
- **"Continue watching"** shelf — partially watched videos with progress bars
- **"Your Custom Feed"** button (experimental since November 2025) — lets users further customize algorithm preferences

**Feed behavior:**
- Infinite scroll with progressive loading
- Responsive grid: 1–4+ columns depending on viewport width
- Lazy-loaded thumbnails and metadata

---

## 4. Video player — all controls, overlays, and features

### 4a. Bottom control bar (left to right)

- **Play/Pause** (keyboard: **K** or **Spacebar**) — semi-transparent, rounded in the 2025 redesign
- **Next video** (keyboard: **Shift+N**) — skips to next in playlist/autoplay
- **Previous video** (keyboard: **Shift+P**) — returns to previous (in playlist context)
- **Volume slider** — click speaker icon to mute/unmute (**M**); hover reveals horizontal slider; **Up/Down arrows** adjust by 5%
- **Time display** — current time / total duration (e.g., "3:42 / 12:15")
- **Chapter title indicator** — appears above progress bar when chapters exist; clickable to open chapter list
- **Progress/seek bar** — red playback position indicator, gray buffered section, draggable red dot scrubber; shows thumbnail previews on hover; chapter markers as vertical dividers; **"Most Replayed" heat map** graph overlay shows rewatch hotspots
- **Autoplay toggle** — switch to auto-advance to next video
- **Subtitles/CC button** (**C**) — toggles closed captions
- **Settings gear (⚙️)** — opens submenu with:
  - **Playback speed**: 0.25x, 0.5x, 0.75x, Normal, 1.25x, 1.5x, 1.75x, 2x, Custom (slider)
  - **Quality**: Auto, 144p, 240p, 360p, 480p, 720p, 720p60, 1080p, 1080p60, 1440p, 1440p60, 2160p (4K), 4320p (8K); "Higher picture quality" and "Data saver" presets; Premium-enhanced 1080p bitrate option
  - **Subtitles/CC**: language selection, auto-generated options, auto-translate to any language
  - **Ambient mode**: on/off — projects soft color glow matching video content behind the player
  - **Stable volume**: normalizes audio levels across videos
  - **Annotations** (legacy, largely deprecated)
  - **Audio track**: when multiple language dubs are available (expanded 2024–2025 with AI autodubbing)
- **Miniplayer button** (**I**) — shrinks to small floating player in bottom-right corner
- **Theater mode button** (**T**) — expands player width to fill browser viewport
- **Fullscreen button** (**F**) — true full-screen mode; **Escape** exits

### 4b. Player overlays and interactive elements

- **Large center play/pause icon** — appears on click/tap and fades
- **Double-click seek** — left side rewinds 10s, right side forwards 10s (cumulative on repeated taps)
- **Long-press 2x speed** — hold anywhere on video to play at 2x; releases on lift
- **End screens** — appear in final 5–20 seconds: subscribe button, video/playlist suggestions, channel icon, external link cards (creator-configured)
- **Info cards ("i" icon)** — small teardrop icon in top-right; card types: video, playlist, channel, link, poll, donation; appear as slide-in panels
- **Channel watermark/branding** — small channel avatar in bottom-right corner; hovering shows subscribe button
- **Ad overlays**: pre-roll, mid-roll, post-roll, bumper (6s non-skippable), non-skippable (15–30s), skippable (skip button appears after 5s with countdown), overlay banner ads (bottom of player)
- **Skip ad button** with countdown timer and ad progress bar
- **360° / VR controls** — drag-to-look interface for immersive video; gyroscope support
- **HDR / Dolby Vision indicators** — badge in quality selector
- **AirPlay / Chromecast button** — appears when compatible devices detected; opens cast dialog listing available devices
- **Picture-in-Picture** — browser-native PiP via right-click or button; creates floating window that persists across tabs/apps

### 4c. Right-click context menu

- Loop
- Copy video URL
- Copy video URL at current time
- Copy embed code
- Copy debug info
- Stats for nerds (displays: Video ID/sCPN, viewport dimensions, current/optimal resolution, volume/normalized, codecs, connection speed, network activity, buffer health, mystery text/dropped frames, live latency for streams)

### 4d. Complete keyboard shortcuts

**Playback:** K/Spacebar (play/pause), J (rewind 10s), L (forward 10s), Left/Right arrows (±5s), Home (start), End (end), 0–9 (jump to 0%–90%), comma/period (frame step when paused), Shift+< / Shift+> (decrease/increase speed)

**Volume:** M (mute), Up/Down arrows (±5%)

**Navigation:** F (fullscreen), T (theater), I (miniplayer), Escape (exit), Shift+N/P (next/previous), Ctrl+Left/Right (next/previous chapter), / (focus search bar)

**Captions:** C (toggle CC), O (caption text opacity), W (caption background opacity), +/- (caption font size)

**Other:** Shift+? (shortcuts overlay)

---

## 5. Watch page — below the player

### 5a. Video metadata and engagement row

- **Video title** — full title, expandable
- **View count and upload date** — e.g., "1.2M views · 3 days ago"
- **Hashtags** — clickable, link to hashtag topic pages

**Channel info bar:**
- Channel avatar (circular, links to channel page)
- Channel name (with verification badge if applicable)
- Subscriber count (e.g., "12.5M subscribers")
- **Subscribe button** — red when unsubscribed, gray when subscribed; bell icon dropdown for notification level: All / Personalized / None
- **Join button** — channel membership tiers with pricing, perks, custom badges, and emoji
- **Thanks ($) button** — Super Thanks one-time tip with dollar amount selection and animated highlight

**Engagement action buttons (pill-shaped row):**
- **Like (👍)** with count — includes dynamic animated effects for certain content categories (music notes, clapboard, sports icon) per the October 2025 redesign
- **Dislike (👎)** — functional but count hidden from public since November 2021
- **Share** — opens share dialog
- **Download** — Premium-only offline download with quality selector
- **Clip** — creates 5–60 second shareable clip with custom title
- **Save** — opens playlist picker: Watch Later, user playlists, "Create new playlist"
- **Three-dot overflow menu (⋮)**: Report, Open transcript, Show description

### 5b. Description box

- **Collapsed view**: first ~100–200 characters, view count, upload date, hashtags; "...more" expander
- **Expanded view** contains: full description text (up to 5,000 chars), clickable timestamps/chapters, external links, hashtags, credits and collaborators, Content ID music info, shopping/product links, license type, video category, "Show less" collapser
- **"In this video"** section — auto-detected people, places, and topics
- **Chapters list** — clickable chapter titles with timestamps
- **Key moments / Important moments** — algorithmically highlighted sections

### 5c. Transcript panel

- Activated via "Show transcript" in description or three-dot menu
- Timestamped text (clickable timestamps jump to that point)
- Searchable text field
- Auto-scroll toggle (syncs with playback)
- Language selector (auto-generated and manual captions)
- Toggle between "Timestamps" and "Segments" view

### 5d. Merchandise and commerce shelves

- **Merchandise shelf** — product cards from linked stores (Teespring/Spring, Shopify, etc.) with images, names, prices
- **Ticketing shelf** — event ticket links
- **Gaming info shelf** — game title, platform, store links
- **Shopping tags** — product stickers tagged by creator, up to 60 per video
- **Movie/show purchase or rent** — pricing tiers for buy/rent with quality options

### 5e. Comments section

- **Comment count** — e.g., "2,345 Comments"
- **Sort options**: Top comments (default), Newest first
- **Comment input**: "Add a comment..." with profile avatar; supports bold, italic, strikethrough, timestamps (auto-linked), @mentions, emoji, hashtags
- **Individual comment features**: user avatar, username (with badges: Creator, Verified, Member), relative timestamp, comment text with "Read more" for long comments, Like button with count, Dislike button (no count), Reply button, three-dot menu (Report, Edit/Delete if own comment, Pin if creator)
- **Pinned comments** — creator-pinned comment at top with "Pinned by [channel]" label
- **Creator hearts** — heart icon on comments hearted by the creator
- **Reply threads** — redesigned in October 2025 with Reddit-style threading; nested replies; "View X replies" expander
- **Super Thanks highlights** — colored comment backgrounds for tippers
- **30-second voice replies** (December 2025) — creators can respond with audio messages
- **"Comments are turned off"** state for disabled comments

### 5f. Suggested videos sidebar (desktop right column)

- **"Up Next"** label with autoplay toggle
- Related video cards: thumbnail, title, channel, views, age, three-dot menu
- **Playlist panel** — if watching from playlist: playlist title, video list, progress indicator, shuffle/loop buttons
- **Chat replay** — for live streams and premieres: scrollable chat with Super Chat highlights
- **Mix playlist suggestions** — auto-generated endless playlists

---

## 6. Sharing, clipping, and saving

### Share dialog
- **Copy link** button (short youtu.be/ URL)
- **Start at** checkbox with timestamp field
- **Embed** tab: iframe code with options for start time, player controls, privacy-enhanced mode
- **Social sharing buttons**: Twitter/X, Facebook, WhatsApp, Email, Reddit, Telegram, Pinterest, LinkedIn, Tumblr, VK (varies by region)

### Clip creation
- Clip button opens editor: drag start/end markers on timeline, 5–60 second range, custom title field (max 140 chars), generates shareable clip URL

### Save options
- **Save to Watch Later** — clock icon; keyboard shortcut available
- **Save to playlist** — "+" button opens picker with all user playlists, search field, "Create new playlist" option (title, visibility: Public/Unlisted/Private)
- **Add to queue** — temporary session queue for immediate watching; queue panel in miniplayer

---

## 7. Search — filters, sorting, and results

**Search results page layout:** video results, channel results (with subscriber count and video count), playlist results, movie/show results, shelf groupings, "People also searched for" suggestions, "Did you mean..." corrections, hashtag results.

**Filter categories (updated January 2026):**

- **Upload date**: Today, This week, This month, This year (some date filters removed in Jan 2026 overhaul as "not working as expected")
- **Type**: Video, Channel, Playlist, Movie, Show, Shorts (new Jan 2026 filter)
- **Duration**: Under 4 minutes, 4–20 minutes, Over 20 minutes
- **Features**: Live, 4K, HD, Subtitles/CC, Creative Commons, 360°, VR180, 3D, HDR, Location, Purchased
- **Sort by** (renamed "Prioritize" in Jan 2026): Relevance, Upload date, Popularity (replaced "View count" — now factors watch time and engagement signals, not just views)

---

## 8. YouTube Shorts — format and UI

Shorts has become YouTube's dominant format with **200 billion daily views** as of early 2026.

**Format:**
- Vertical (9:16) video, maximum **3 minutes** (extended from 60s in 2026)
- Loops continuously by default
- Desktop: displayed in centered vertical frame with up/down navigation arrows; swipe or scroll to advance
- New view counting (March 2025): any play or replay counts as 1 view with no minimum watch time

**Shorts player controls:**
- **Like** button with count
- **Dislike** button
- **Comments** — sliding panel from right side
- **Share** button
- **Remix** button — create new Short using this video's audio/format
- **Three-dot menu**: Description, Don't recommend, Report, Send feedback, Captions toggle
- **Subscribe button** — overlaid on channel avatar
- **Sound/music attribution bar** — bottom of screen, links to original audio source
- **Progress bar** — thin line at bottom showing position in the loop
- **Shopping product stickers** — redesigned June 2025 to show actual product images

**Shorts-specific features:**
- Separate recommendation engine fully decoupled from long-form content (late 2025)
- AI enhancements (deblurring, denoising, skin smoothing) applied automatically with opt-out controls
- Image posts integrating into Shorts feed
- Collaboration feature: up to 5 co-authors per Short
- URLs in Shorts descriptions/comments are non-clickable (since August 2023)
- Shorts can now be filtered in/out of search results (January 2026)

---

## 9. Channel pages — all tabs and features

**Channel header:**
- Banner/header art (2560×1440 recommended)
- Channel avatar, name, handle (@handle), verification badge
- Subscriber count, video count, joined date
- **Subscribe** button with notification bell (All / Personalized / None)
- **Join** button (membership tiers)
- Channel links (social media, website)

**Channel tabs:**

- **Home** — featured/trailer video, creator-customized sections and shelves, "For You" personalized shelf
- **Videos** — all long-form uploads; sort: Latest, Popular, Oldest; filter by type
- **Shorts** — grid of short-form content
- **Live** — past and current livestreams
- **Playlists** — all public playlists; sort: Date added (newest/oldest), Last video added, A–Z
- **Community / Posts** — text posts, image posts (up to 5 images), polls (text/image/GIF), quizzes, video links; interactions: Like, Dislike, Comment, Share; pinned posts
- **Courses** — structured educational content with sequential lessons
- **Channels** — featured/subscribed channels curated by creator
- **Store** — merchandise integration (where enabled)
- **Podcasts** — podcast episodes and series (where applicable)
- **About** / more info — full description, links, location, joined date, total views, email for business inquiries

**Membership features (Join button):**
- Multiple tiers with pricing ($0.99–$99.99/month)
- Tier perks: custom badges, custom emoji, members-only videos, community posts, live chats
- Gift memberships

---

## 10. Live streaming viewer experience

- **Live chat panel** — collapsible; real-time message feed with username, avatar, badges
- **Super Chat** — paid highlighted messages with color coding by amount (blue $1–$1.99, cyan $2–$4.99, green $5–$9.99, yellow $10–$19.99, orange $20–$49.99, magenta $50–$99.99, red $100–$500); pinned at top for duration proportional to amount
- **Super Stickers** — animated paid stickers in chat
- **Jewels** — digital currency for gift-giving during livestreams with seasonal offerings
- **Polls** — creator-initiated polls displayed in chat
- **Chat modes**: Top Chat (filtered), Live Chat (all messages), Members-only, Slow mode (configurable delay)
- **Live DVR** — scrub backward in live stream without losing live position
- **Live viewer count** — real-time display
- **"Remind me"** button for upcoming premieres/scheduled streams
- **Premiere countdown** with chat enabled before video starts
- **Chat replay** on VODs — full synchronized chat playback
- **Smart Q&A sticker** (October 2025) — AI-powered suggested questions for mobile livestreams

---

## 11. Playlists — creation, management, types

**User-created playlists:**
- Title, description, visibility (Public / Unlisted / Private)
- Add/remove videos, drag-and-drop reorder
- Collaborative playlists (shareable edit link)
- Playlist page UI: Play All, Shuffle, Share, Save (bookmark entire playlist), three-dot menu (Edit, Delete, Report)
- Metadata: video count, total duration, last updated, creator

**System playlists:**
- **Watch Later** — quick-save queue
- **Liked Videos** — auto-populated from likes
- **History** — watch history (with pause/clear options)

**Auto-generated playlists:**
- **My Mix** — personalized music mix
- **Discover Mix** — new music discovery
- **Video-seeded Mixes** — based on a specific video ("Mix – [video title]")
- **Artist mixes** — genre and artist-based

**YouTube Music cross-visibility** — playlists created in YouTube Music appear in YouTube library and vice versa

---

## 12. Library / "You" page


Sections displayed on the You/Library page:
- **History** — Watch history and Search history; pause history toggle; clear history options
- **Watch Later** — saved videos queue (see below for fallback logic)
- **Liked Videos** — all liked content
- **Playlists** — all user playlists with "New playlist" creation button
- **Your videos** — link to uploaded content (redirects to Studio)
- **Your clips** — all created clips
- **Your movies & TV** — purchased/rented content
- **Your courses** — enrolled course content
- **Downloads** — offline content (Premium only)
- **Manage all history** link → Google My Activity

### Watch Later Fallback Logic

If YouTube's internal API (`browse/edit_playlist`) is unavailable (due to authentication, scope, or API restrictions), GlassTube provides a local "GlassTube Watch Later" playlist as a fallback. A clear disclaimer is shown in the UI when the fallback is active. The fallback playlist is not synced with your YouTube account and will not appear on youtube.com or other YouTube apps. This ensures users always have a working Watch Later queue, but with clear separation between the official and local playlists.

---

## 13. Notifications — types and settings

**Notification types:** new uploads from subscribed channels, live stream starts, premiere countdowns, community posts, comment replies, @mentions, subscription milestones, recommendation digests, channel membership alerts, Super Chat/Thanks notifications.

**Per-channel notification levels:** All (every upload), Personalized (algorithmic selection), None

**Notification settings page:** email notification toggles per category, push notification toggles, recommendation frequency, subscription notifications, activity on your channel/comments, product updates.

---

## 14. Settings page — every category

**Account:** Google Account info, channel management, add/manage channels, Brand Account management

**Notifications:** granular email and push notification preferences per category (subscriptions, recommended videos, activity on your channel, activity on your comments, replies, mentions, shared content, product updates and announcements)

**Playback and performance:** AV1 video codec settings, autoplay on/off, inline playback, subtitle preferences (default language, always show captions), playback speed memory, Ambient mode default, Stable volume default

**Privacy:** manage watch history (pause/delete), manage search history (pause/delete), keep all subscriptions private, ad personalization link

**Connected apps:** third-party apps with YouTube API access; revoke access

**Billing and payments:** Premium/Music membership management, payment method, billing history

**Downloads:** download quality defaults (Premium), storage management, Wi-Fi only toggle

**Advanced settings:** delete channel, move channel to Brand Account, content language preference, multiple language audio tracks preference

**Appearance** (in account dropdown): Device theme / Dark theme / Light theme

**Restricted Mode** (in account dropdown): content filtering toggle

**Language and Location** (in account dropdown): interface language, content region

---

## 15. YouTube Premium — all tiers and features

### Premium (Individual: $15.99/mo, Family: $26.99/mo, Student: $8.99/mo, Annual: $159.99/yr — prices as of April 10, 2026)
- **Ad-free viewing** across all content types (pre-roll, mid-roll, banner, Shorts ads all removed)
- **Background play** — audio continues when tab/app is backgrounded or screen locked
- **Offline downloads** — quality options (720p, 1080p, or "Enhanced" bitrate for Premium)
- **Picture-in-Picture** on all platforms
- **YouTube Music Premium included** — ad-free music streaming, offline, background play, audio-only mode, 300M+ tracks
- **Enhanced bitrate 1080p** — higher quality encoding at same resolution
- **Jump ahead** feature
- **Cross-device resume** — save and sync playback position
- **Smart downloads** — auto-download recommended videos on Wi-Fi
- **Premium member badge** in comments/chat
- **125+ million subscribers** globally (March 2025 figure)

### Premium Lite ($8.99/mo — launched March 2025)
- **Ad-free on most non-music videos** (ads remain on music videos, Shorts, and while browsing/searching)
- **Background play** (added February 2026)
- **Offline downloads** (added February 2026)
- **No YouTube Music Premium**
- Available in **20+ countries** including US, UK, Canada, Brazil, India, Australia, Germany, France, and expanding

---

## 16. Platform capabilities and special features

### Casting and remote playback
- **Chromecast** — cast button in player, device selection dialog, remote queue management, quality selection
- **AirPlay** — supported on Safari and some Chromium browsers on macOS
- Cast dialog shows available devices on local network

### Picture-in-Picture
- Browser-native PiP (Chrome, Firefox, Safari, Edge) — floating resizable/repositionable window
- Controls within PiP: play/pause, close, seek (browser-dependent), next/previous track
- Persists across tabs and (on macOS) across desktop Spaces

### Accessibility
- **Caption customization**: font family (7 options), font size (50%–400%), font color (8 options), font opacity (4 levels), background color (8 options), background opacity (4 levels), window color, window opacity, character edge style (none, drop shadow, raised, depressed, outline)
- Full keyboard navigation and tab focus indicators
- ARIA labels on all interactive elements
- Screen reader support
- High contrast mode compatibility

### Content labels and information panels
- **Age restriction gates** — sign-in required overlay
- **Content warnings** — disturbing/sensitive content interstitials
- **Fact-check panels** — third-party fact-checker labels below certain videos
- **Wikipedia context panels** — for topics prone to misinformation
- **Copyright/Content ID notices** — visible to viewers on affected videos
- **AI content disclosure labels** — creators must disclose realistic altered/synthetic content

### URL structures
- `youtube.com/watch?v=[ID]` — standard watch page
- `youtu.be/[ID]` — short share URL
- `youtube.com/shorts/[ID]` — Shorts player
- `youtube.com/@[handle]` — channel page
- `youtube.com/playlist?list=[ID]` — playlist page
- `youtube.com/feed/subscriptions` — subscriptions feed
- `youtube.com/feed/history` — watch history
- `youtube.com/feed/library` — library page

### Other platform features
- **YouTube Handles (@username)** — unique identifiers for all channels
- **YouTube Playables** — casual games playable within YouTube
- **YouTube Courses** — structured educational content
- **YouTube Shopping** — product tags, affiliate program (eligible at 500 subscribers as of March 2026), in-app checkout planned for 2026
- **Premieres** — scheduled video launches with countdown and live chat
- **Hype button** — engagement feature for emerging creators
- **Gemini-powered "Ask" button** — AI Q&A about the video being watched, available in 5 languages, testing on TVs and consoles
- **AI autodubbing** — multi-language AI voice translation averaging 6M+ daily viewers
- **Multi-language audio tracks** — viewer-selectable dubs (human and AI-generated)

---

## 17. Report and flag features

**Report video categories:** Sexual content, Violent or repulsive content, Hateful or abusive content, Harassment or bullying, Harmful or dangerous acts, Misinformation, Child abuse, Spam or misleading, Captions issue, Infringes my rights, Promotes terrorism, Suicide or self-harm.

**Other report surfaces:** Report comment, Report channel, Report community post, Report live chat message, Report playlist, Send general feedback (with screenshot annotation tool).

---

## 18. Third-party enhancement ecosystem

### SponsorBlock
An open-source crowdsourced extension that auto-skips unwanted segments using community-submitted timestamps via a privacy-preserving hash-based API.

**All 9+ segment categories with color codes on the seek bar:**
- **Sponsor** (green) — paid promotion, paid referrals, direct advertisements
- **Unpaid/Self-Promotion** (yellow) — merchandise plugs, Patreon mentions, channel promotions
- **Interaction Reminder** (purple) — subscribe, like, comment, notification bell reminders
- **Intro** (cyan) — animated or static intro sequences
- **Outro** (blue) — end credits, outros, post-content material
- **Preview/Recap** (light blue) — preview of upcoming content or recap of previous episodes
- **Music: Non-Music Section** (orange) — non-music portions in music videos
- **Filler/Tangent** (dark green) — tangential content, off-topic jokes, padding
- **Exclusive Access** — paywall or limited access warnings
- **Point of Interest / Highlight** — single timestamp marking the video's most interesting moment

**Action types per segment:** auto-skip, manual skip (show skip button), mute, full (labels entire video), poi (single point)

**Additional features:** community voting/reputation system for submission accuracy; chapter generation from segments; open database downloadable by anyone; color-coded timeline overlay on YouTube's progress bar; integrated into ReVanced, SmartTube, LibreTube, FreeTube, Piped, mpv, yt-dlp.

### Return YouTube Dislike (RYD)
Restores the dislike count removed by Google in November 2021. Uses a combination of **archived pre-removal data** (~1 billion videos), **extension user behavior extrapolation**, and **view/like ratio estimates**. Shows dislike count next to the dislike button and a like/dislike ratio bar. Public API at returnyoutubedislikeapi.com. Accuracy decreases for unpopular videos uploaded after December 13, 2021. **927,000+ Firefox users**, 4.7-star rating.

### DeArrow
Built by the same developer as SponsorBlock, DeArrow replaces clickbait titles and thumbnails with community-sourced alternatives. Users submit replacement titles (plain text) and thumbnail timestamps (random screenshots from the video). Voting system ranks submissions. **Fallback behavior** when no submission exists: auto-formats original title to sentence case (preserving acronyms and proper nouns) and shows a random timestamp screenshot (server-side generated, avoiding SponsorBlock-flagged segments). "Show original" peek button available. **70,000+ active Chrome users**. Optional $1 license.

### Enhancer for YouTube
Popular extension adding: custom toolbar below player, volume boost beyond 100%, screenshot capture, cinema mode (dims page around player), auto-quality selection, auto-expand description, custom playback speed controls (including speeds above 2x), custom CSS theme support, AMOLED dark theme, mouse wheel volume control, always-on-top PiP window, configurable keyboard shortcuts, and remove annotations.

### Ad blocking landscape (2025–2026)
YouTube has **aggressively escalated** anti-adblock enforcement: detection warnings, playback restrictions, three-video limits before blocking, and server-side ad injection (significantly harder to block). **uBlock Origin** remains the most effective browser-based blocker but requires frequent filter updates. YouTube continuously patches exploits. **Alternative approaches**: DNS-level blocking (Pi-hole, NextDNS) with limited effectiveness against server-side injection, alternative frontends (Piped more resilient than Invidious in 2026, with ~15 surviving instances vs ~3), and Premium as the sanctioned ad-free solution.

### Other notable extensions
- **Unhook YouTube** — removes recommendation feeds, hides sidebar, comments, end screens, trending; focus mode
- **BlockTube** — block specific channels and videos by keyword
- **YouTube Redux** — restores older YouTube layout elements (classic like bar, etc.)
- **yt-dlp** — command-line video/audio download tool; supports SponsorBlock chapter embedding, metadata extraction, format selection

---

## 19. macOS-specific considerations for a native client

Building a native YouTube client for macOS involves these platform-specific concerns:

**Video playback and performance:**
- **AVFoundation / AVKit** — Apple's native video frameworks for hardware-accelerated decoding; support H.264, HEVC (H.265), VP9 (via VideoToolbox on Apple Silicon), and AV1 (hardware decode on M3/M4 chips)
- **Hardware acceleration** — Apple Silicon (M1–M4) provides efficient hardware decoding; Intel Macs limited to H.264/HEVC hardware decode
- **HDR support** — Extended Dynamic Range (EDR) on XDR displays (MacBook Pro, Pro Display XDR); Dolby Vision metadata passthrough
- **Spatial Audio / Dolby Atmos** — supported on macOS with AirPods Pro/Max or built-in speakers on MacBook Pro 14"/16"

**macOS integration points:**
- **Media key integration** — play/pause/skip via F7/F8/F9 keyboard media keys; integrate with `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`
- **Native Picture-in-Picture** — AVKit PiP window floats above all apps and Spaces; persists across desktop switches; native resize/reposition controls
- **Touch Bar** (older MacBook Pro models) — playback controls, timeline scrubber, volume
- **Notification Center** — push notifications for uploads, live streams, comments using `UNUserNotificationCenter`
- **Dock badge** — unread notification count on app icon
- **Menu bar** — standard macOS menu bar conventions (File, Edit, View, Window, Help menus); playback controls under dedicated Playback menu
- **Window management** — full screen, Split View, Stage Manager (macOS Ventura+) compatibility; resize/restore states
- **Handoff / Continuity** — resume watching across iPhone/iPad/Mac via `NSUserActivity`
- **Trackpad gestures** — pinch to zoom video, swipe navigation between sections, force click for peek
- **System appearance** — automatic Dark/Light mode matching via `NSApp.effectiveAppearance`
- **Keychain** — secure credential storage for Google OAuth tokens
- **Universal Links** — register for youtube.com URL handling to open links in native app
- **App Sandbox** — required for Mac App Store distribution; limits file system and network access
- **Energy efficiency** — respect App Nap; use efficient rendering to minimize battery drain; adaptive quality based on power source

**Authentication and API:**
- **Google OAuth 2.0** desktop flow (loopback redirect or device code flow)
- **YouTube Data API v3** — official API for subscriptions, playlists, search, comments (quota-limited at 10,000 units/day default)
- **Innertube API** — YouTube's internal API used by the website and apps; undocumented but widely reverse-engineered; provides richer data including recommendations, continuation tokens, and player configs; no official support or stability guarantees

**Architecture decisions:**
- **Swift/SwiftUI** — native performance, full macOS API access, App Store compatible, but requires building all UI from scratch
- **Electron/WebView** — faster development wrapping web content, but heavier resource usage and less native feel
- **WKWebView hybrid** — embed YouTube's web player for video while building native UI around it; balances development speed and native integration
- **Existing macOS YouTube clients**: FreeTube (Electron-based, open source, privacy-focused), IINA (native media player that can play YouTube URLs via yt-dlp), MacTube (lightweight browser wrapper)

**macOS Sequoia and Tahoe considerations:**
- Desktop widgets for subscription feed or Watch Later
- iPhone app mirroring (if building for both platforms)
- Enhanced window tiling APIs
- Updates to AVFoundation and Metal rendering

---

## Conclusion: a platform of compounding complexity

YouTube's feature surface in 2026 is staggeringly large. The October 2025 Material Design 3 overhaul reskinned virtually every control with translucent, pill-shaped elements and dynamic like animations, while functional additions like threaded comments, voice replies, the Gemini "Ask" button, and the Premium Lite tier have expanded the platform's capabilities in every direction. The January 2026 search filter redesign and Shorts-specific filters reflect YouTube's ongoing tension between its short-form and long-form identities. For anyone building a native client, the most important architectural insight is that YouTube effectively operates **five separate recommendation systems** (Home, Suggested, Search, Shorts, Subscriptions), each requiring distinct UI treatment. The third-party ecosystem—SponsorBlock, DeArrow, RYD—has matured into a reliable parallel infrastructure with open APIs, making integration straightforward for custom clients. On macOS specifically, the M3/M4 hardware AV1 decode support and AVKit's native PiP make 2026 an opportune moment for a native YouTube client that can outperform both the web experience and Electron wrappers.