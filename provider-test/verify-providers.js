const axios = require('axios');

// Test items: The Batman (TMDB: 414906, IMDb: tt1877830)
const TEST_TMDB = "414906";
const TEST_IMDB = "tt1877830";

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
        const fullMovieUrl = `${node.movie_url}${activeId}`;
        
        console.log(`Analyzing [${node.name}] (Targeting ID Style: ${node.id_type.toUpperCase()})...`);
        const startTime = Date.now();
        
        try {
            const response = await axios.get(fullMovieUrl, { 
                headers: networkHeaders,
                timeout: 5000 // 5-second gate limit
            });
            
            const duration = Date.now() - startTime;
            
            // Check if the server responds with a valid web page framework
            if (response.status === 200 && response.data.length > 1000) {
                console.log(`  MOVIE --> ✅ ONLINE | Code: 200 OK | Latency: ${duration}ms | Data Packets Intact`);
                healthyCount++;
            } else {
                console.log(`  MOVIE --> ⚠️ BLANK | Code: ${response.status} | Short/empty page layout string received.`);
            }
        } catch (error) {
            const duration = Date.now() - startTime;
            console.log(`  MOVIE --> ❌ DEAD | Error: ${error.message} | Latency: ${duration}ms`);
        }
        console.log("-----------------------------------------------------------------");
    }
    
    console.log(`\\nDIAGNOSTIC COMPLETION STATUS: [${healthyCount}/${targetNodes.length}] EMULATORS VERIFIED FUNCTIONAL.`);
}

executeDiagnostics();