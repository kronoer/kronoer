import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this is Kronoer Preview, the app for trying Kronoer before its
/// release, beside the stable app. It is the `preview` build flavor;
/// builds without a flavor are the stable app.
final isPreviewProvider = Provider<bool>((ref) => appFlavor == 'preview');

/// The Preview's name, which is not translated.
const previewName = 'Kronoer Preview';
