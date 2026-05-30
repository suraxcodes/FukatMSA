class AdBlockService {
  static final Set<String> adBlocklistDomains = {
    'doubleclick.net',
    'googlesyndication.com',
    'adnxs.com',
    'popads.net',
    'popcash.net',
    'exoclick.com',
    'trafficjunky.net',
  };

  static const String sandboxJsInjection = '''
    // Override window.open to block popups
    window.open = function() {
      console.log('Popup blocked by sandbox');
      return null;
    };
    
    // Hide overlay divs with high z-index
    var style = document.createElement('style');
    style.innerHTML = `
      div[style*="z-index: 9999"], 
      div[style*="z-index: 10000"] {
        display: none !important;
        pointer-events: none !important;
      }
    `;
    document.head.appendChild(style);
    
    // Suppress alerts and confirms
    window.alert = function() { console.log('Alert blocked'); };
    window.confirm = function() { console.log('Confirm blocked'); return false; };
  ''';
}
