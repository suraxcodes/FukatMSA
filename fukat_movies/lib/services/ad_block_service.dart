import 'dart:convert';

class AdBlockService {
  // 1. Unified Network Domain Blocklist
  static const Set<String> adBlocklistDomains = {
    'doubleclick.net', 'googlesyndication.com', 'adnxs.com', 
    'popads.net', 'popcash.net', 'exoclick.com', 'trafficjunky.net',
    'ajio.com', 'myntra.com', 'flipkart.com', 'amazon.in', // Direct E-commerce popup destinations
    'adsterra', 'propellerads', 'infolinks', 'revenuehits', // Major popup networks
    'awin1.com', 'admitad.com', 'cuelinks.com', 'vcommission.com', // Affiliate trackers
    'vidsrcme.ru', // Block direct domain navigation attempts
    'masonerthoria.shop', 'videouv.online', 'jape.hoosgowdemodedimouts.cyou'
  };

  // 2. Custom Layout Selector Map matched directly to your 4 active providers
  static const Map<String, List<String>> _uiSelectors = {
    'player.videasy.net': ['.logo', '.header-menu', '.footer', '.share-btn'],
    'vidsrcme.ru': ['#logo', '.top-navigation', '.server-sidebar', '.ads-overlay', '.ad', '.ads', '.popup', '#ad-banner', '.banner', '.advertisement', '.video-wrapper .ads', '.player-overlay'],
    'www.2embed.cc': ['#logo-container', '.margin-ads', '.player-banner'],
    'www.nontongo.win': ['.logo-text', '.header-wrapper', '.bottom-nav', '#notice-box', '.no-stream', '.error-message'],
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
        window.open = function() { console.log('Blocked window.open'); return null; };
        window.alert = function() { console.log('Blocked alert'); return null; };
        window.confirm = function() { console.log('Blocked confirm'); return false; };
        // Block direct navigation attempts via location.assign/replace (safe)
        try {
          window.location.assign = function(url){ console.log('Blocked location.assign:', url); };
          window.location.replace = function(url){ console.log('Blocked location.replace:', url); };
        } catch (e) { console.warn('Assign/replace override failed', e); }
        // Removed href override – not reliable across browsers

        // Log any navigation attempts to blocked domains
        console.log('AdBlocker active for URL:', window.location.href);

        // 3. (Removed aggressive z-index hider because it breaks legitimate video players)


        // 4. Aggressive click interceptor to kill popup ads & redirects
        document.addEventListener('click', function(e) {
          // Block any link that tries to navigate away from the current domain
          let a = e.target.closest('a');
          if (a && a.host && a.host !== window.location.host) {
            e.preventDefault();
            e.stopPropagation();
            console.log("Blocked ad popup link: ", a.href);
            return false;
          }
        }, true); // useCapture = true to intercept before anything else

        // 5. Guard against iframe source rewrites (e.g., 2embed) using a MutationObserver
        (function(){
          const originalHref = window.location.href;
          const observer = new MutationObserver(()=>{
            if(window.location.href !== originalHref){
              console.log('🔒 Blocked navigation attempt via iframe src change:', window.location.href);
              window.location.href = originalHref; // revert
            }
          });
          observer.observe(document.documentElement, { attributes:true, childList:true, subtree:true });
        })();

        // 5. Force the internal HTML5 video element to fill the layout bounds
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
