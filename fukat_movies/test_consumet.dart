import 'package:http/http.dart' as http;

void main() async {
  try {
    final url = Uri.parse('https://consumet-org-clone.vercel.app/meta/anilist-manga/One%20Piece');
    final res = await http.get(url).timeout(Duration(seconds: 10));
    print('Consumet Clone: ${res.statusCode}');
  } catch(e) {
    print('Error');
  }
}
