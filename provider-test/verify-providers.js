const axios = require('axios');

// Test items: One Piece Anime (TMDB: 37854, IMDb: tt0388629)
const TEST_TMDB = "37854";
const TEST_IMDB = "tt0388629";
const TEST_SEASON = "1";
const TEST_EPISODE = "1";

const targetNodes = [
    {
      "name": "Videasy",
      "id_type": "tmdb",
      "format_style": "slash",
      "movie_url": "https://player.videasy.net/movie/",
      "tv_url": "https://player.videasy.net/tv/"
    },
    {
      "name": "VidSrcMe RU",
      "id_type": "imdb",
      "format_style": "query",
      "movie_url": "https://vidsrcme.ru/embed/movie?imdb=",
      "tv_url": "https://vidsrcme.ru/embed/tv?imdb="
    },
    {
      "name": "2Embed",
      "id_type": "imdb",
      "format_style": "query_mix",
      "movie_url": "https://www.2embed.cc/embed/",
      "tv_url": "https://www.2embed.cc/embedtv/"
    },
    {
      "name": "NontonGo",
      "id_type": "tmdb",
      "format_style": "slash",
      "movie_url": "https://www.nontongo.win/embed/movie/",
      "tv_url": "https://www.nontongo.win/embed/tv/"
    },
    {
      "name": "vidsrc.fyi",
      "id_type": "tmdb",
      "format_style": "query",
      "movie_url": "https://vidsrc.fyi/embed/movie/",
      "tv_url": "https://vidsrc.fyi/embed/tv/"
    },

    {
      "name": "vidnest.fun",
      "id_type": "tmdb",
      "format_style": "slash",
      "movie_url": "https://vidnest.fun/movie/",
      "tv_url": "https://vidnest.fun/tv/",
      "anime_url": "https://vidnest.fun/anime/",
      "anime_phase": "https://vidnest.fun/animepahe/"
    },
    {
      "name": "vidlink.pro",
      "id_type": "tmdb",
      "format_style": "slash",
      "movie_url": "https://vidlink.pro/movie/",
      "tv_url": "https://vidlink.pro/tv/"
    },
    {
      "name": "vidfast.net",
      "id_type": "tmdb",
      "format_style": "slash",
      "movie_url": "https://www.vidfast.net/movie/",
      "tv_url": "https://www.vidfast.net/tv/"
    },
    {
      "name": "111movie",
      "id_type": "tmdb",
      "format_style": "slash",
      "movie_url": "https://111movies.net/movie/",
      "tv_url": "https://111movies.net/tv/"
    },
    {
      "name": "AutoEmbed",
      "id_type": "tmdb",
      "format_style": "dash",
      "movie_url": "https://autoembed.co/movie/tmdb/",
      "tv_url": "https://autoembed.co/tv/tmdb/"
    }
];

const networkHeaders = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
};

async function executeDiagnostics() {
    console.log("=================================================================");
    console.log("RUNNING CORRECTED EMBED MATRIX SPECIFICATION DIAGNOSTICS          ");
    console.log("=================================================================\\n");
    
    let healthyCount = 0;

    for (const node of targetNodes) {
        // Correctly select the proper ID token based on provider type
        const activeId = (node.id_type === "tmdb") ? TEST_TMDB : TEST_IMDB;
        
        let fullTvUrl = "";
        if (node.format_style === "slash") {
            fullTvUrl = `${node.tv_url}${activeId}/${TEST_SEASON}/${TEST_EPISODE}`;
        } else if (node.format_style === "query") {
            // For vidsrc.fyi query style might be base?imdb=id&s=season&e=episode
            // But we already updated vidsrc.fyi to slash.
            fullTvUrl = `${node.tv_url}${activeId}&s=${TEST_SEASON}&e=${TEST_EPISODE}`;
        } else if (node.format_style === "dash") {
            // AutoEmbed style
            fullTvUrl = `${node.tv_url}${activeId}-${TEST_SEASON}-${TEST_EPISODE}`;
        } else {
            fullTvUrl = `${node.tv_url}${activeId}/${TEST_SEASON}/${TEST_EPISODE}`;
        }
        
        console.log(`Analyzing [${node.name}] (Targeting ID Style: ${node.id_type.toUpperCase()})...`);
        const startTime = Date.now();
        
        try {
            const response = await axios.get(fullTvUrl, { 
                headers: networkHeaders,
                timeout: 5000 // 5-second gate limit
            });
            
            const duration = Date.now() - startTime;
            
            // Check if the server responds with a valid web page framework
            if (response.status === 200 && response.data.length > 1000) {
                console.log(`  ANIME TV --> ✅ ONLINE | URL: ${fullTvUrl} | Latency: ${duration}ms`);
                healthyCount++;
            } else {
                console.log(`  ANIME TV --> ⚠️ BLANK | URL: ${fullTvUrl} | Code: ${response.status}`);
            }
        } catch (error) {
            const duration = Date.now() - startTime;
            console.log(`  ANIME TV --> ❌ DEAD | Error: ${error.message} | URL: ${fullTvUrl} | Latency: ${duration}ms`);
        }
        console.log("-----------------------------------------------------------------");
    }
    
    console.log(`\\nDIAGNOSTIC COMPLETION STATUS: [${healthyCount}/${targetNodes.length}] EMULATORS VERIFIED FUNCTIONAL.`);
}

executeDiagnostics();