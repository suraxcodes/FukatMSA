import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ad_block_config.dart';

class AdBlockService {
  // Remote config URL (GitHub raw). Replace with your actual URL.
  static const String _remoteConfigUrl = 'https://raw.githubusercontent.com/suraxcodes/FukatMSA/main/adblock_config.json';

  // In‑memory cache of the loaded config
  static AdBlockConfig? _cachedConfig;

  // Fallback static data (used when remote fetch fails)
  static const Set<String> _fallbackDomains = {
    'doubleclick.net', 'googlesyndication.com', 'adnxs.com',
    'popads.net', 'popcash.net', 'exoclick.com', 'trafficjunky.net',
    'ajio.com', 'myntra.com', 'flipkart.com', 'amazon.in',
    'adsterra', 'propellerads', 'infolinks', 'revenuehits',
    'awin1.com', 'admitad.com', 'cuelinks.com', 'vcommission.com',
    'vidsrcme.ru',
    'masonerthoria.shop', 'videouv.online', 'jape.hoosgowdemodedimouts.cyou',
  };

  static const Map<String, List<String>> _fallbackSelectors = {
    'player.videasy.net': ['.logo', '.header-menu', '.footer', '.share-btn'],
    'vidsrcme.ru': ['#logo', '.top-navigation', '.server-sidebar', '.ads-overlay', '.ad', '.ads', '.popup', '#ad-banner', '.banner', '.advertisement', '.video-wrapper .ads', '.player-overlay'],
    'www.2embed.cc': ['#logo-container', '.margin-ads', '.player-banner'],
    'www.nontongo.win': ['.logo-text', '.header-wrapper', '.bottom-nav', '#notice-box', '.no-stream', '.error-message'],
  };

  // Load config from remote or cache, fallback to static constants.
  static Future<AdBlockConfig> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'adBlockConfigCache';
    try {
      final response = await http.get(Uri.parse(_remoteConfigUrl));
      if (response.statusCode == 200) {
        await prefs.setString(cacheKey, response.body);
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _cachedConfig = AdBlockConfig.fromJson(json);
        return _cachedConfig!;
      }
    } catch (e) {
      // ignore errors, will try cache/fallback
    }
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      final json = jsonDecode(cached) as Map<String, dynamic>;
      _cachedConfig = AdBlockConfig.fromJson(json);
      return _cachedConfig!;
    }
    _cachedConfig = AdBlockConfig(domains: _fallbackDomains, selectors: _fallbackSelectors);
    return _cachedConfig!;
  }

  static Future<bool> isAdDomain(String url) async {
    final config = await _loadConfig();
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    return config.domains.any((domain) => uri.host.contains(domain));
  }

  // Dynamic Script Builder – async
  static Future<String> getUiCleanerScript(String currentUrl) async {
    final config = await _loadConfig();
    final uri = Uri.tryParse(currentUrl);
    final domain = uri?.host ?? '';
    final selectors = config.selectors[domain] ?? ['.header', '.logo', 'footer'];
    final targetListJson = jsonEncode(selectors);
    final domainBlockJson = jsonEncode(config.domains.toList());
    return """
      (function() {
        const selectorsToHide = $targetListJson;
        const blockedDomains = $domainBlockJson;
        selectorsToHide.forEach(selector => {
          document.querySelectorAll(selector).forEach(el => {
            el.style.setProperty('display', 'none', 'important');
          });
        });
        window.open = function() { console.log('Blocked window.open'); return null; };
        window.alert = function() { console.log('Blocked alert'); return null; };
        window.confirm = function() { console.log('Blocked confirm'); return false; };
        try {
          window.location.assign = function(url){ console.log('Blocked location.assign:', url); };
          window.location.replace = function(url){ console.log('Blocked location.replace:', url); };
        } catch (e) { console.warn('Assign/replace override failed', e); }
        console.log('AdBlocker active for URL:', window.location.href);
        document.addEventListener('click', function(e) {
          let a = e.target.closest('a');
          if (a && a.host && a.host !== window.location.host) {
            e.preventDefault();
            e.stopPropagation();
            console.log('Blocked ad popup link: ', a.href);
            return false;
          }
        }, true);
        (function(){
          const originalHref = window.location.href;
          const observer = new MutationObserver(() => {
            if(window.location.href !== originalHref){
              console.log('🔒 Blocked navigation attempt via iframe src change:', window.location.href);
              window.location.href = originalHref;
            }
          });
          observer.observe(document.documentElement, { attributes:true, childList:true, subtree:true });
        })();
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
