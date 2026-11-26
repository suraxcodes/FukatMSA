
---

# Master Implementation Roadmap & Project Plan (v5.5)

## Phase 1: Pre-Development Environment Setup & Diagnostic Automation

Before writing your mobile frontend code, you must guarantee that your external scraping cluster is alive and serving actual data. Websites update their layouts constantly, which breaks scrapers. This script tests your full 6-tier provider array simultaneously using masqueraded mobile network headers.

### Step 1.1: Local Testing Environment Initialization

1. Open your computer's terminal or command prompt.
2. Create a clean folder for this test and enter it:
```bash
mkdir provider-test && cd provider-test

```


3. Initialize a standard Node.js project:
```bash
npm init -y

```


4. Install **Axios**, the network library used to make the API requests:
```bash
npm install axios

```



### Step 1.2: Create the Pre-Validation Script

Create a file named `verify-providers.js` inside that folder, open it in a text editor, and paste this exact production code:

```javascript
const axios = require('axios');

// Configure your backend endpoints here
const targetNodes = [
    { id: 1, name: "NetMirror Core Engine", url: "https://your-scarperapi-node.vercel.app/api/netmirror", type: "json_stream", testPayload: "?title=The+Family+Man" },
    { id: 2, name: "KMMovies Premium Mirror", url: "https://your-scarperapi-node.vercel.app/api/kmmovies", type: "json_stream", testPayload: "?title=The+Family+Man" },
    { id: 3, name: "VidLink Base Engine", url: "https://your-vidlink-node.onrender.com/api", type: "json_stream", testPayload: "?imdb=tt1375666" },
    { id: 4, name: "Consumet Aggregator Core", url: "https://your-consumet-node.onrender.com/movies/flixhq/watch", type: "json_stream", testPayload: "?episodeId=movie/tt1375666" },
    { id: 5, name: "CinePro Secondary Linker", url: "https://your-cinepro-node.onrender.com/api", type: "json_stream", testPayload: "?title=Inception" },
    { id: 6, name: "VidSrc Embed Fallback", url: "https://vidsrc.to/embed/movie/tt1375666", type: "iframe_sandbox", testPayload: "" }
];

const networkHeaders = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
    "X-Requested-With": "com.netmirror.app" // Mimics the official application identity
};

async function executeDiagnostics() {
    console.log("=================================================================");
    console.log("INITIALIZING MEDIA PROVIDER TIER DIAGNOSTIC PRE-VALIDATION SCAN  ");
    console.log("=================================================================\\n");
    
    let activeCounts = 0;

    for (const node of targetNodes) {
        const fullTestUrl = `${node.url}${node.testPayload}`;
        console.log(`Analyzing Tier ${node.id} [${node.name}]...`);
        
        const timestampStart = Date.now();
        
        try {
            const response = await axios.get(fullTestUrl, { 
                headers: networkHeaders,
                timeout: 4000 // 4-second maximum cutoff to ensure speed
            });
            
            const processDuration = Date.now() - timestampStart;
            
            if (node.type === "json_stream") {
                const dataString = JSON.stringify(response.data);
                const hasMediaLinks = dataString.includes('.m3u8') || dataString.includes('.mp4') || dataString.includes('sources');
                
                if (response.status === 200 && hasMediaLinks) {
                    console.log(`--> RESULT: HEALTHY | Code: 200 OK | Latency: ${processDuration}ms`);
                    activeCounts++;
                } else {
                    console.log(`--> RESULT: UNHEALTHY | Status 200 but payload missing raw media path (.m3u8/.mp4)`);
                }
            } else if (node.type === "iframe_sandbox") {
                if (response.status === 200 && response.data.includes('<iframe')) {
                    console.log(`--> RESULT: HEALTHY iframe target verified | Latency: ${processDuration}ms`);
                    activeCounts++;
                } else {
                    console.log(`--> RESULT: UNHEALTHY iframe target structural markup missing from DOM returns`);
                }
            }
        } catch (error) {
            const processDuration = Date.now() - timestampStart;
            console.log(`--> RESULT: CRITICAL CORRUPTION DETECTED`);
            if (error.response) {
                console.log(`    Status Code Returned: ${error.response.status} (${error.response.statusText})`);
            } else {
                console.log(`    Network Exception Error: ${error.message}`);
            }
        }
        console.log("-----------------------------------------------------------------");
    }
    
    console.log(`\\nSCAN SUMMARY: [${activeCounts}/${targetNodes.length}] NODES ONLINE.`);
}

executeDiagnostics();

```

### Step 1.3: Run the Verification

Run the file in your terminal:

```bash
node verify-providers.js

```

* **What to check:** Ensure your main streaming tiers come back healthy. If any of them return dead or empty links, swap them immediately out for your fallback alternatives like **SuperEmbed** (`api.superembed.cc`) or **Hydrostream** (`hydro.cm/api`) before you write frontend code.

---

## Phase 2: Decoupled Backend Server Deployment

Your scrapers must live completely independent of your main frontend code. This keeps your user-facing store app completely blank and legal.

### Step 2.1: Fork the Scraper Repositories

1. Go to your GitHub account.
2. Fork the open-source scraper code templates (e.g., `github.com/Anshu78780/ScarperApi`) to your personal profile.
3. Clean and check for vulnerabilities locally:
```bash
npm audit fix

```



### Step 2.2: Deploy to Free Cloud Servers ($0 Fees)

* **For Vercel (Next.js scripts):** Link your GitHub account to Vercel.com, select your forked `ScarperApi` repository, and hit deploy. Vercel automatically creates secure serverless URLs for your APIs.
* **For Render (Express/Node engines like Consumet/VidLink):** Create a free account on Render.com, select **New Web Service**, connect your GitHub repo, set the build script to `npm install` and start script to `npm start`.

---

## Phase 3: Google Play Store Frontend Client Implementation

The app uploaded to the app store must be a completely legal, clean movie tracker with no built-in media players or video stream links.

### Step 3.1: Public Catalog Interface (100% Legal)

* **The Data Hook:** Code your dashboard layout grids to query the open, public **TMDB API** (`api.themoviedb.org`). This pulls down standard text metadata, descriptions, cast bios, and movie posters.
* **Local Lists:** Save watch histories and watchlists on-device inside a local SQLite database or simple shared preferences cache.

### Step 3.2: Native Video Player Setup (HLS Chunk Management)

1. Use an advanced native player framework (like `better_player_plus` or `media_kit`).
2. Set up the engine to grab the `.m3u8` master file link when passed down by an extension.
3. Program the player to read the manifest resolution profiles natively, automatically building a 1080p, 720p, or 480p user toggle menu.
4. Turn on Adaptive Bitrate (ABR) processing so the player automatically requests smaller or larger video segments (chunks) based on the user's internet connection speed.

---

## Phase 4: Integration Layer, Sandboxing, & Data Sync

This is the bridge that securely links your legal frontend to your custom scraper extensions.

### Step 4.1: Custom Ingestion Input Box

1. Build an input field inside your app's setting panel called **"Import Custom Repository Extension"**.
2. When a user pastes an external community JSON configuration link, save that link securely to local storage.
3. At runtime, the app fetches that JSON map to instantly unlock streaming links for the search titles.

### Step 4.2: ID Translation & WebView Sandbox Guard

* **The Conversion Hook:** Scrapers like VidSrc need alphanumeric IMDb IDs (`tt1234567`), but TMDB uses numbers. Build a translator using the TMDB external ID lookup endpoint (`/movie/{id}/external_ids`) to automatically switch IDs before querying your scraper tiers.
* **The Popup Blocker Sandbox:** For Tier 6 web embeds, lock the iframe inside a strict WebView container. You must explicitly disable script popups and set a URL filter list to instantly block known third-party advertising strings from loading:
```dart
javaScriptCanOpenWindowsAutomatically: false,
supportMultipleWindows: false,
contentBlockers: [
  ContentBlocker(
    trigger: ContentBlockerTrigger(urlFilter: ".*googlesyndication.*|.*doubleclick.*|.*popads.*"),
    action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK)
  )
]

```



### Step 4.3: Syncing Progress with Supabase

Run this exact query inside your Supabase SQL editor to create a relational database table that tracks video runtime timestamps securely:

```sql
CREATE TABLE continue_watching (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  media_id VARCHAR(255) NOT NULL,
  current_time_seconds INTEGER NOT NULL DEFAULT 0,
  total_duration_seconds INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE continue_watching ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own playback data" ON continue_watching FOR ALL USING (auth.uid() = user_id);

```

* **Security Guard:** Always pull and cache the active user JWT token on app launch to prevent 401 connection unauthorized errors during playback syncing loops.

---

## Phase 5: Safe Monetization Framework Activation

Never link your direct bank details or standard Stripe/Google Play sub systems to streaming copyrighted files. Use these safe, insulated methods instead:

* **Method A (Premium UI Enhancements):** Charge native app store subscriptions **only** for purely visual or functional interface updates (like cloud backup sync options or unlocking premium UI dashboard templates). You are legally charging for layout software configurations, not videos.
* **Method B (External Crypto Repository Gates):** Keep your actual app completely free. Host your scraper extension files on an independent, anonymous web dashboard locked behind a crypto gateway that accepts Monero, Bitcoin, or USDT.
* **Method C (Compliant In-App Store Ad Networks):** Integrate standard ad networks (like Google AdMob). Program the layout to only display banner or interstitial ads when users are browsing completely legal panels, such as their on-device watchlist page or cast summaries pulled from public TMDB assets.