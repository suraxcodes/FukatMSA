import re

with open("lib/screens/player_screen.dart", "r", encoding="utf-8") as f:
    content = f.read()

# First, remove ALL occurrences of onGeolocationPermissionsShowPrompt to clean up the mess
content = re.sub(r'[\s]*onGeolocationPermissionsShowPrompt:\s*\(.*?\},', '', content, flags=re.DOTALL)

# Now carefully insert it into HeadlessInAppWebView
headless_search = "        onLoadStop: (controller, url) async {"
headless_replace = """        onGeolocationPermissionsShowPrompt: (controller, origin) async {
          print("Auto-denying geolocation request from $origin");
          return GeolocationPermissionShowPromptResponse(origin: origin, allow: false, retain: true);
        },
        onLoadStop: (controller, url) async {"""
# We want the first occurrence of onLoadStop which is inside HeadlessInAppWebView
content = content.replace(headless_search, headless_replace, 1)

# Now insert it into InAppWebView
inapp_search = "          onLoadStop: (controller, url) async {"
inapp_replace = """          onGeolocationPermissionsShowPrompt: (controller, origin) async {
            print("Auto-denying geolocation request from $origin");
            return GeolocationPermissionShowPromptResponse(origin: origin, allow: false, retain: true);
          },
          onLoadStop: (controller, url) async {"""
# This will replace all remaining ones (there should only be one)
content = content.replace(inapp_search, inapp_replace)

with open("lib/screens/player_screen.dart", "w", encoding="utf-8") as f:
    f.write(content)
