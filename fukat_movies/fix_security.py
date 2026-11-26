import sys
import re

file_path = r'c:\Users\Sarvesh\Documents\2025Projects\fukatMovies\fukat_movies\lib\screens\player_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace HeadlessInAppWebView settings
content = re.sub(
    r'mediaPlaybackRequiresUserGesture: false,',
    r'mediaPlaybackRequiresUserGesture: false,\n        useOnDownloadStart: true,\n        supportMultipleWindows: false,\n        javaScriptCanOpenWindowsAutomatically: false,',
    content,
    count=1
)

# Add onDownloadStartRequest to HeadlessInAppWebView
content = re.sub(
    r'initialUserScripts: UnmodifiableListView<UserScript>\(\[',
    r'''onDownloadStartRequest: (controller, downloadRequest) async {
        print("Blocked background download request: ${downloadRequest.url}");
      },
      initialUserScripts: UnmodifiableListView<UserScript>([''',
    content,
    count=1
)

# Replace InAppWebView settings
content = re.sub(
    r'javaScriptCanOpenWindowsAutomatically: true,\s*supportMultipleWindows: true,',
    r'javaScriptCanOpenWindowsAutomatically: false,\n            supportMultipleWindows: false,\n            useOnDownloadStart: true,',
    content,
    count=1
)

# Add onDownloadStartRequest to InAppWebView
content = re.sub(
    r'onWebViewCreated: \(controller\) \{',
    r'''onDownloadStartRequest: (controller, downloadRequest) async {
            print("Blocked user download request: ${downloadRequest.url}");
          },
          onWebViewCreated: (controller) {''',
    content,
    count=1
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Applied security fixes to InAppWebView and HeadlessInAppWebView!")
