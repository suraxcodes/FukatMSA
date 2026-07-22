import 'package:http/http.dart' as http; void main() async { var res = await http.get(Uri.parse('https://vidsrc.me/embed/movie?tmdb=1083381')); print(res.statusCode); }
