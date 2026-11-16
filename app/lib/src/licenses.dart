import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _licenses = [
  ('Marck Script', 'assets/fonts/marck_script/OFL.txt'),
  ('Plus Jakarta Sans', 'assets/fonts/plus_jakarta_sans/OFL.txt'),
  ('Literata', 'assets/fonts/literata/OFL.txt'),
  ('Keyline Icons', 'assets/icons/LICENSE'),
];

void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (font, path) in _licenses) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString(path));
    }
  });
}
