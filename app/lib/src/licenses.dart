import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bundled assets under their own license.
const _licenses = [('Keyline Icons', 'assets/icons/LICENSE')];

void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, path) in _licenses) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString(path));
    }
  });
}
