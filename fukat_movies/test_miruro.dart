import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final payload = {
    "path": "episodes",
    "method": "GET",
    "query": {"anilistId": 207141}, // Chainsmoker Cat / Dandadan
    "body": null,
    "version": "0.1.0",
  };
  
  final jsonString = json.encode(payload);
  final encodedReq = base64Url.encode(utf8.encode(jsonString)).replaceAll('=', '');
  final uri = Uri.parse("https://www.miruro.tv/api/secure/pipe?e=$encodedReq");
  
  final headers = {
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Origin": "https://www.miruro.tv",
    "Referer": "https://www.miruro.tv/",
    "Sec-Ch-Ua": "\"Chromium\";v=\"116\", \"Not)A;Brand\";v=\"24\", \"Google Chrome\";v=\"116\"",
    "Sec-Ch-Ua-Mobile": "?0",
    "Sec-Ch-Ua-Platform": "\"Windows\"",
    "Sec-Fetch-Dest": "empty",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "same-origin",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36"
  };

  print("Fetching $uri");
  try {
    final response = await http.get(uri, headers: headers);
    print("Status: ${response.statusCode}");
    if (response.statusCode == 200) {
      print("SUCCESS!");
    } else {
      print("Body: ${response.body.substring(0, 200)}...");
    }
  } catch (e) {
    print("Error: $e");
  }
}
