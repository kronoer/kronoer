import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where Kronoer Preview is released.
final releasesApi = Uri.https(
  'api.github.com',
  '/repos/kronoer/kronoer/releases',
  {'per_page': '20'},
);

/// The device's side of the check for a new Preview: the one request it
/// makes, and the browser it sends the user to.
abstract interface class UpdatePlatform {
  /// The releases GitHub lists, newest first, as decoded JSON. The request
  /// carries nothing but [userAgent] and what every request does. Throws
  /// when the request fails.
  Future<Object?> fetchReleases({required String userAgent});

  /// Opens [url] in the browser. Returns false when there is none.
  Future<bool> openInBrowser(Uri url);
}

/// Android's: `dart:io` for the request, and the app's own platform channel
/// for the browser.
class AndroidUpdatePlatform implements UpdatePlatform {
  const AndroidUpdatePlatform();

  static const _channel = MethodChannel('app.kronoer/browser');

  /// More than GitHub's answer for 20 releases with their notes.
  static const _maxBytes = 4 << 20;

  @override
  Future<Object?> fetchReleases({required String userAgent}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = userAgent;
    try {
      final request = await client.getUrl(releasesApi);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub answered ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw const HttpException('GitHub answered too much');
        }
      }
      return jsonDecode(utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> openInBrowser(Uri url) async =>
      await _channel.invokeMethod<bool>('open', url.toString()) ?? false;
}

final updatePlatformProvider = Provider<UpdatePlatform>(
  (ref) => const AndroidUpdatePlatform(),
);
