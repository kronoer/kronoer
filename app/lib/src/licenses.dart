import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _fontLicenses = [
  ('Marck Script', 'assets/fonts/marck_script/OFL.txt'),
  ('Plus Jakarta Sans', 'assets/fonts/plus_jakarta_sans/OFL.txt'),
  ('Literata', 'assets/fonts/literata/OFL.txt'),
];

/// Adds the OFL text of every bundled font to the licenses page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (font, path) in _fontLicenses) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString(path));
    }
  });
}
