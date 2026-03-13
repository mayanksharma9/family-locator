import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyLocatorApp());
}

class FamilyLocatorApp extends StatelessWidget {
  const FamilyLocatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Family Locator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF245CFF)),
        useMaterial3: true,
      ),
      home: const FamilyLocatorHomePage(),
    );
  }
}

class FamilyMember {
  const FamilyMember({
    required this.name,
    required this.role,
    required this.location,
    required this.lastUpdated,
    required this.isSharing,
    required this.isCurrentUser,
  });

  final String name;
  final String role;
  final LatLng location;
  final DateTime lastUpdated;
  final bool isSharing;
  final bool isCurrentUser;
}

class FamilyLocatorHomePage extends StatefulWidget {
  const FamilyLocatorHomePage({super.key});

  @override
  State<FamilyLocatorHomePage> createState() => _FamilyLocatorHomePageState();
}

class _FamilyLocatorHomePageState extends State<FamilyLocatorHomePage> {
  final MapController _mapController = MapController();

  bool _sharingEnabled = true;
  bool _consentAccepted = false;
  bool _busy = false;
  String? _status;
  Position? _currentPosition;

  static final List<FamilyMember> _sampleMembers = [
    FamilyMember(
      name: 'Leo',
      role: 'You',
      location: const LatLng(37.7749, -122.4194),
      lastUpdated: DateTime.now().subtract(const Duration(minutes: 2)),
      isSharing: true,
      isCurrentUser: true,
    ),
    FamilyMember(
      name: 'Ava',
      role: 'Family',
      location: const LatLng(37.7849, -122.4094),
      lastUpdated: DateTime.now().subtract(const Duration(minutes: 1)),
      isSharing: true,
      isCurrentUser: false,
    ),
    FamilyMember(
      name: 'Noah',
      role: 'Family',
      location: const LatLng(37.7649, -122.4294),
      lastUpdated: DateTime.now().subtract(const Duration(minutes: 4)),
      isSharing: true,
      isCurrentUser: false,
    ),
  ];

  List<FamilyMember> get _members {
    if (_currentPosition == null) {
      return _sampleMembers;
    }

    return _sampleMembers.map((member) {
      if (!member.isCurrentUser) {
        return member;
      }
      return FamilyMember(
        name: member.name,
        role: member.role,
        location: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        lastUpdated: DateTime.now(),
        isSharing: _sharingEnabled,
        isCurrentUser: true,
      );
    }).toList();
  }

  Future<void> _enableSharing() async {
    setState(() {
      _busy = true;
      _status = 'Requesting location permission…';
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _busy = false;
        _status = 'Location services are off. Turn them on in system settings.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _busy = false;
        _sharingEnabled = false;
        _status = 'Permission not granted. This app only shares location with consent.';
      });
      return;
    }

    final position = await Geolocator.getCurrentPosition();

    setState(() {
      _busy = false;
      _consentAccepted = true;
      _sharingEnabled = true;
      _currentPosition = position;
      _status = 'Location sharing is on. Replace the sample backend to sync with your family.';
    });

    _mapController.move(LatLng(position.latitude, position.longitude), 13);
  }

  void _disableSharing() {
    setState(() {
      _sharingEnabled = false;
      _status = 'Location sharing is off on this device.';
    });
  }

  Future<void> _refreshLocation() async {
    if (!_sharingEnabled) {
      setState(() {
        _status = 'Turn sharing back on before refreshing location.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Refreshing your location…';
    });

    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _busy = false;
        _currentPosition = position;
        _status = 'Location refreshed just now.';
      });
      _mapController.move(LatLng(position.latitude, position.longitude), 13);
    } catch (_) {
      setState(() {
        _busy = false;
        _status = 'Could not refresh location right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    final currentUser = members.firstWhere((member) => member.isCurrentUser);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Locator'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refreshLocation,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh location',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _sharingEnabled ? Icons.location_on : Icons.location_off,
                          color: _sharingEnabled ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _sharingEnabled
                                ? 'Sharing is visible and enabled on this device.'
                                : 'Sharing is disabled on this device.',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This app is designed for explicit family consent. Do not install or use it secretly.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _enableSharing,
                          icon: const Icon(Icons.verified_user),
                          label: Text(_consentAccepted ? 'Re-check permissions' : 'Enable sharing'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _disableSharing,
                          icon: const Icon(Icons.pause_circle_outline),
                          label: const Text('Stop sharing'),
                        ),
                      ],
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 12),
                      Text(_status!),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: currentUser.location,
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.family_locator',
                    ),
                    MarkerLayer(
                      markers: members
                          .where((member) => member.isSharing)
                          .map(
                            (member) => Marker(
                              point: member.location,
                              width: 120,
                              height: 60,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: member.isCurrentUser
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      member.name,
                                      style: TextStyle(
                                        color: member.isCurrentUser
                                            ? Theme.of(context).colorScheme.onPrimary
                                            : Theme.of(context).colorScheme.onSecondaryContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Icon(
                                    Icons.location_pin,
                                    size: 28,
                                    color: member.isCurrentUser ? Colors.redAccent : Colors.blueAccent,
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final member = members[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  leading: CircleAvatar(
                    child: Text(member.name.characters.first),
                  ),
                  title: Text(member.name),
                  subtitle: Text(
                    '${member.role} • ${member.isSharing ? 'Sharing' : 'Paused'} • updated ${_formatAgo(member.lastUpdated)}',
                  ),
                  trailing: Icon(
                    member.isSharing ? Icons.check_circle : Icons.pause_circle,
                    color: member.isSharing ? Colors.green : Colors.orange,
                  ),
                );
              },
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemCount: members.length,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAgo(DateTime timestamp) {
    final delta = DateTime.now().difference(timestamp);
    if (delta.inMinutes < 1) {
      return 'just now';
    }
    if (delta.inHours < 1) {
      return '${delta.inMinutes}m ago';
    }
    return '${delta.inHours}h ago';
  }
}
