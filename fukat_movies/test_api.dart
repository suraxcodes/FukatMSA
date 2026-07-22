import 'package:http/http.dart' as http; void main() async { var res = await http.get(Uri.parse('https://vidlink.pro/api/video/movie/1083381')); print(res.body); }
