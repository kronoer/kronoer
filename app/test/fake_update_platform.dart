import 'package:kronoer/src/update/update_platform.dart';

/// GitHub as the check sees it.
class FakeUpdatePlatform implements UpdatePlatform {
  Object? answer = releases(['v0.1.0']);
  Object? error;
  int fetched = 0;
  String? userAgent;
  bool browser = true;
  final opened = <Uri>[];

  @override
  Future<Object?> fetchReleases({required String userAgent}) async {
    fetched++;
    this.userAgent = userAgent;
    if (error case final error?) throw error;
    return answer;
  }

  @override
  Future<bool> openInBrowser(Uri url) async {
    opened.add(url);
    return browser;
  }
}

/// Published Previews tagged [tags], as GitHub lists them.
List<Map<String, Object?>> releases(List<String> tags) => [
  for (final tag in tags) {'tag_name': tag, 'draft': false, 'prerelease': true},
];
