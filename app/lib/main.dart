import 'package:material_ui/material_ui.dart';
import 'package:kronoer/src/rust/api/version.dart';
import 'package:kronoer/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const KronoerApp());
}

class KronoerApp extends StatelessWidget {
  const KronoerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Kronoer', home: PlaceholderScreen());
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [const Text('Kronoer'), Text('core ${coreVersion()}')],
        ),
      ),
    );
  }
}
