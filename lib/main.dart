import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/milky_provider.dart';
import 'screens/name_screen.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MilkyChatApp());
}

class MilkyChatApp extends StatelessWidget {
  const MilkyChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MilkyProvider(),
      child: MaterialApp(
        title: 'MilkyChat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.deepPurple,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        home: const _EntryGate(),
      ),
    );
  }
}

/// Checks if user already has a saved name; if so, auto-init and go to home.
class _EntryGate extends StatefulWidget {
  const _EntryGate();

  @override
  State<_EntryGate> createState() => _EntryGateState();
}

class _EntryGateState extends State<_EntryGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final name = await MilkyProvider.getSavedName();
    if (name != null && name.isNotEmpty && mounted) {
      try {
        final provider = context.read<MilkyProvider>();
        await provider.init(name);
      } catch (e) {
        debugPrint('MilkyChat init error: $e');
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        return;
      }
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const NameScreen();
  }
}
