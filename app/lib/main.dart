import 'package:material_ui/material_ui.dart';

void main() {
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
    return const Scaffold(body: Center(child: Text('Kronoer')));
  }
}
