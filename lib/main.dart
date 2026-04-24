import 'package:flutter/material.dart';
import 'map_bridge.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Friendship Radius',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MapTestScreen(),
    );
  }
}

class MapTestScreen extends StatefulWidget {
  const MapTestScreen({super.key});

  @override
  State<MapTestScreen> createState() => _MapTestScreenState();
}

class _MapTestScreenState extends State<MapTestScreen> {
  final _mapBridge = MapBridge();
  bool _mapLoaded = false;
  String _status = 'Loading map...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initMap());
  }

  void _initMap() {
    // PUT YOUR API KEY HERE
    const apiKey = 'bm_1776994862_KawMha9ThhfhcffRIuVgjLRcynTD5DEk';

    final success = _mapBridge.init(apiKey);
    setState(() {
      _mapLoaded = success;
      final error = _mapBridge.lastError;
      _status = success
          ? 'Map loaded!'
          : error.isEmpty
              ? 'Map failed to load'
              : 'Map failed to load: $error';
    });

    if (success) {
      // Test: add a pin at Marina Bay Sands
      Future.delayed(const Duration(seconds: 3), () {
        _mapBridge.addFriendPin(
          id: 'test1',
          lat: 1.2834,
          lng: 103.8607,
          color: '#EF4444',
          label: 'A',
        );
        _mapBridge.flyTo(1.2834, 103.8607, zoom: 14);
        setState(() => _status = 'Pin added at Marina Bay Sands!');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Friendship Radius',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(_status),
            ],
          ),
        ),
      ),
    );
  }
}
