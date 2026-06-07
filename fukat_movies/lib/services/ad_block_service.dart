import 'dart:convert';

class AdBlockService {
  // 1. Unified Network Domain Blocklist
  static const Set<String> adBlocklistDomains = {
    'doubleclick.net', 'googlesyndication.com', 'adnxs.com',
    'popads.net', 'popcash.net', 'exoclick.com', 'trafficjunky.net',
    'ajio.com',
    'myntra.com',
    'flipkart.com',
    'amazon.in', // Direct E-commerce popup destinations
    'adsterra',
    'propellerads',
    'infolinks',
    'revenuehits', // Major popup networks
    'awin1.com',
    'admitad.com',
    'cuelinks.com',
    'vcommission.com', // Affiliate trackers
    'vidsrcme.ru', // Block direct domain navigation attempts
    'masonerthoria.shop', 'videouv.online', 'jape.hoosgowdemodedimouts.cyou',
  };

  // 2. Custom Layout Selector Map matched directly to your 4 active providers
  static const Map<String, List<String>> _uiSelectors = {
    'player.videasy.net': ['.logo', '.header-menu', '.footer', '.share-btn'],
    'vidsrcme.ru': [
      '#logo',
      '.top-navigation',
      '.server-sidebar',
      '.ads-overlay',
      '.ad',
      '.ads',
      '.popup',
      '#ad-banner',
      '.banner',
      '.advertisement',
      '.video-wrapper .ads',
      '.player-overlay',
    ],
    'www.2embed.cc': ['#logo-container', '.margin-ads', '.player-banner'],
    'www.nontongo.win': [
      '.logo-text',
      '.header-wrapper',
      '.bottom-nav',
      '#notice-box',
      '.no-stream',
      '.error-message',
    ],
    // New working providers (empty list prevents fallback CSS from hiding player controls)
    'vidsrc.fyi': [],
    'vidnest.fun': [],
    '111movies.net': [],
    'www.vidfast.net': [],
  };

  // Providers to bypass ad-blocking temporarily for testing
  static const List<String> _bypassAdBlockProviders = [
    'videasy.net',
    'videasy.to',
    '2embed.cc',
  ];

  static bool shouldBypassAdBlock(String url) {
    return _bypassAdBlockProviders.any((domain) => url.contains(domain));
  }

  // 3. Dynamic Script Builder
  static String getUiCleanerScript(String currentUrl) {
    if (shouldBypassAdBlock(currentUrl)) {
      return ""; // Return empty script to bypass ad blocker
    }

    final uri = Uri.tryParse(currentUrl);
    final domain = uri?.host ?? '';

    // If a domain isn't explicitly listed, do not hide anything to avoid breaking player UI
    final selectors = _uiSelectors[domain] ?? [];
    final targetListJson = jsonEncode(selectors);

    return """
      (function() {
        const selectorsToHide = $targetListJson;
        
        // 1. Instantly hide layout headers, logos, and bars
        selectorsToHide.forEach(selector => {
          document.querySelectorAll(selector).forEach(el => {
            el.style.setProperty('display', 'none', 'important');
          });
        });

        // 2. Suppress malicious popups with a "Soft Blocker" (returns a dummy object so player scripts don't crash)
        window.open = function() { 
          console.log('Soft-blocked window.open'); 
          return { closed: false, close: function(){}, focus: function(){}, length: 1 }; 
        };
        window.alert = function() { console.log('Blocked alert'); return null; };
        window.confirm = function() { console.log('Blocked confirm'); return false; };
        try {
          window.location.assign = function(url){ console.log('Blocked location.assign:', url); };
          window.location.replace = function(url){ console.log('Blocked location.replace:', url); };
        } catch (e) { console.warn('Assign/replace override failed', e); }

        // Log any navigation attempts to blocked domains
        console.log('AdBlocker active for URL:', window.location.href);

        // 3. (Removed aggressive z-index hider because it breaks legitimate video players)


        // 4. Soft Click Interceptor: Let the Dart WebView layer block the actual navigation
        // so we don't accidentally kill Javascript click handlers needed by the player.
        document.addEventListener('click', function(e) {
          let a = e.target.closest('a');
          if (a && a.host && a.host !== window.location.host) {
            console.log("Ad link clicked, deferring block to Dart layer: ", a.href);
            // We NO LONGER call preventDefault() here, otherwise the player's internal click handler breaks.
          }
        }, true);


        // 5. Removed aggressive video repositioning so custom player controls are not hidden.
      })();
    """;
  }
}
