
import 'dart:convert';
import 'dart:io';

void main() async {
  final res = await HttpClient().getUrl(Uri.parse('https://gogoanime3.co/search.html?keyword=naruto')).then((req) => req.close());
  final body = await res.transform(utf8.decoder).join();
  final regex = RegExp(r'href=.(/category/[^\x22]+).\s+title=.\x22?([^\x22]+)\x22?', caseSensitive: false);
  final match = regex.firstMatch(body);
  if (match != null) {
    print('Found: \');
  } else {
    print('Not found');
  }
}

