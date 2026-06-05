import 'dart:convert';

class AdBlockService {
  // 1. Unified Network Domain Blocklist
  static const Set<String> adBlocklistDomains = {
    'doubleclick.net', 'googlesyndication.com', 'adnxs.com', 
    'popads.net', 'popcash.net', 'exoclick.com', 'trafficjunky.net'
  };

  // 2. Custom Layout Selector Map matched directly to your 4 active providers
  static const Map<String, List<String>> _uiSelectors = {
    'player.videasy.net': ['.logo', '.header-menu', '.footer', '.share-btn'],
    'vidsrcme.ru': ['#logo', '.top-navigation', '.server-sidebar', '.ads-overlay'],
    'www.2embed.cc': ['.player-top-bar', '#logo-container', '.margin-ads', '.player-banner'],
    'www.nontongo.win': ['.logo-text', '.header-wrapper', '.bottom-nav', '#notice-box'],
  };

  // 3. Dynamic Script Builder
  static String getUiCleanerScript(String currentUrl) {
    final uri = Uri.tryParse(currentUrl);
    final domain = uri?.host ?? '';
    
    // Fallback to basic elements if a domain isn't explicitly listed in the selector map
    final selectors = _uiSelectors[domain] ?? ['.header', '.logo', 'footer'];
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

        // 2. Suppress malicious popups and external window hijacks
        window.open = function() { return null; };
        window.alert = function() { return null; };
        window.confirm = function() { return false; };

        // 3. Hide overlay divs with high z-index (generic popups)
        var style = document.createElement('style');
        style.innerHTML = `
          div[style*="z-index: 9999"], 
          div[style*="z-index: 10000"] {
            display: none !important;
            pointer-events: none !important;
          }
        `;
        document.head.appendChild(style);

        // 4. Force the internal HTML5 video element to fill the layout bounds
        const video = document.querySelector('video');
        if (video) {
          video.style.setProperty('position', 'fixed', 'important');
          video.style.setProperty('top', '0', 'important');
          video.style.setProperty('left', '0', 'important');
          video.style.setProperty('width', '100vw', 'important');
          video.style.setProperty('height', '100vh', 'important');
          video.style.setProperty('z-index', '9999', 'important');
        }
      })();
    """;
  }
}
