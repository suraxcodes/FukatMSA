// check_movie_providers.js
// Simple script to verify that selected providers can stream a movie URL.
// It attempts to fetch a known movie page and checks for a non‑trivial response.

const axios = require('axios');

// Test identifiers – choose a popular title.
const TEST_TMDB = "101012"; // The Batman (TMDB)
const TEST_IMDB = "101012"; // The Batman (IMDb)

const providers = [
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
  }
];

const networkHeaders = {
  "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
};

async function testProviders() {
  console.log('=== Provider Movie Availability Check ===');
  let successCount = 0;

  for (const prov of providers) {
    const id = prov.id_type === 'tmdb' ? TEST_TMDB : TEST_IMDB;
    let fullUrl = '';
    // Build URL based on format_style – we only handle the styles used here.
    if (prov.format_style === 'slash') {
      fullUrl = `${prov.movie_url}${id}`;
    } else if (prov.format_style === 'query_mix') {
      // query_mix for 2Embed expects: base + id (same as slash for this endpoint)
      fullUrl = `${prov.movie_url}${id}`;
    } else {
      // fallback – treat as simple concatenation
      fullUrl = `${prov.movie_url}${id}`;
    }

    console.log(`\nTesting [${prov.name}] → ${fullUrl}`);
    const start = Date.now();
    try {
      const resp = await axios.get(fullUrl, { headers: networkHeaders, timeout: 8000 });
      const elapsed = Date.now() - start;
      if (resp.status === 200 && resp.data && resp.data.length > 1000) {
        console.log(`  ✅ SUCCESS | 200 OK | ${elapsed}ms | Response size: ${resp.data.length}`);
        successCount++;
      } else {
        console.log(`  ⚠️ POSSIBLE ISSUE | Status: ${resp.status} | Size: ${resp.data ? resp.data.length : 'N/A'}`);
      }
    } catch (err) {
      const elapsed = Date.now() - start;
      console.log(`  ❌ FAILED | ${err.message} | after ${elapsed}ms`);
    }
  }

  console.log(`\nSummary: ${successCount}/${providers.length} providers returned a viable movie page.`);
}

testProviders();
