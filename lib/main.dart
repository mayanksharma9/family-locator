import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
    required this.id,
    required this.name,
    required this.location,
    required this.lastUpdated,
    required this.isSharing,
    required this.accuracy,
    this.isCurrentUser = false,
  });

  final String id;
  final String name;
  final LatLng? location;
  final DateTime? lastUpdated;
  final bool isSharing;
  final double? accuracy;
  final bool isCurrentUser;

  factory FamilyMember.fromJson(Map<String, dynamic> json, {required String currentUserId}) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    return FamilyMember(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      location: lat == null || lng == null ? null : LatLng(lat, lng),
      lastUpdated: json['updatedAt'] == null ? null : DateTime.tryParse(json['updatedAt'] as String),
      isSharing: json['isSharing'] as bool? ?? false,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      isCurrentUser: (json['id'] as String? ?? '') == currentUserId,
    );
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ConnectionIntent {
  const _ConnectionIntent({
    required this.name,
    required this.roomCode,
    required this.serverUrl,
  });

  final String name;
  final String roomCode;
  final String serverUrl;
}

class FamilyLocatorHomePage extends StatefulWidget {
  const FamilyLocatorHomePage({super.key});

  @override
  State<FamilyLocatorHomePage> createState() => _FamilyLocatorHomePageState();
}

class _FamilyLocatorHomePageState extends State<FamilyLocatorHomePage> {
  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController(text: 'Leo');
  final TextEditingController _roomController = TextEditingController(text: 'HOME123');
  final TextEditingController _serverController = TextEditingController(text: 'ws://10.0.2.2:8080');

  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _sharingEnabled = false;
  bool _isConnected = false;
  bool _isJoining = false;
  bool _autoReconnectEnabled = false;
  int _reconnectAttempts = 0;

  String? _status = 'Enter a visible family code and connect to your relay.';
  String? _roomCode;
  String? _memberId;
  Position? _currentPosition;
  List<FamilyMember> _members = const [];
  _ConnectionIntent? _lastIntent;

  @override
  void dispose() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _socketSubscription?.cancel();
    _positionSubscription?.cancel();
    _channel?.sink.close();
    _nameController.dispose();
    _roomController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _connectAndJoin({bool isReconnect = false}) async {
    FocusScope.of(context).unfocus();
    final name = _nameController.text.trim();
    final roomCode = _roomController.text.trim().toUpperCase();
    final serverUrl = _serverController.text.trim();

    if (name.isEmpty || roomCode.isEmpty || serverUrl.isEmpty) {
      setState(() {
        _status = 'Name, family code, and relay URL are all required.';
      });
      return;
    }

    _lastIntent = _ConnectionIntent(name: name, roomCode: roomCode, serverUrl: serverUrl);
    _autoReconnectEnabled = true;
    _reconnectTimer?.cancel();

    setState(() {
      _isJoining = true;
      _status = isReconnect ? 'Reconnecting to relay…' : 'Checking permission and connecting…';
    });

    final permissionReady = await _ensureLocationReady();
    if (!permissionReady) {
      setState(() {
        _isJoining = false;
      });
      return;
    }

    await _disconnect(clearState: false, allowReconnect: false);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _channel = channel;
      _socketSubscription = channel.stream.listen(
        _handleSocketMessage,
        onError: (Object error) => _handleDisconnect('Relay connection failed: $error'),
        onDone: () => _handleDisconnect('Relay disconnected.'),
      );

      channel.sink.add(jsonEncode({
        'type': 'join',
        'name': name,
        'roomCode': roomCode,
        'isSharing': _sharingEnabled || !isReconnect,
      }));

      setState(() {
        _sharingEnabled = true;
        _roomCode = roomCode;
        _isConnected = true;
        _status = 'Connected. Waiting for room state…';
        _reconnectAttempts = 0;
      });

      _startPingLoop();
      await _publishCurrentLocation();
      _startLocationStream();
    } catch (error) {
      _handleDisconnect('Could not connect to relay: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  void _handleDisconnect(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isConnected = false;
      _status = message;
    });
    _pingTimer?.cancel();
    if (_autoReconnectEnabled) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_lastIntent == null || _isConnected || _isJoining) {
      return;
    }
    _reconnectTimer?.cancel();
    final delaySeconds = (_reconnectAttempts < 5 ? _reconnectAttempts + 1 : 5) * 2;
    _reconnectAttempts += 1;
    setState(() {
      _status = 'Relay offline. Retrying in ${delaySeconds}s…';
    });
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && _autoReconnectEnabled) {
        _connectAndJoin(isReconnect: true);
      }
    });
  }

  Future<bool> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = 'Location services are off. Turn them on first.';
      });
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() {
        _status = 'Permission not granted. This app only shares location with consent.';
      });
      return false;
    }

    return true;
  }

  Future<void> _publishCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      _currentPosition = position;
      _sendLocation(position);
      _moveMapTo(position.latitude, position.longitude);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Connected, but the first location fix is still pending.';
      });
    }
  }

  void _startLocationStream() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((position) {
      _currentPosition = position;
      if (_sharingEnabled && _isConnected) {
        _sendLocation(position);
      }
      _moveMapTo(position.latitude, position.longitude);
    });
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _sendLocation(Position position) {
    _channel?.sink.add(jsonEncode({
      'type': 'location',
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'isSharing': _sharingEnabled,
    }));
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'Sharing live location to family code ${_roomCode ?? '-'}.';
    });
  }

  void _handleSocketMessage(dynamic raw) {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (message['type']) {
      case 'welcome':
        setState(() {
          _status = 'Relay connected. Joining room…';
        });
        break;
      case 'joined':
        setState(() {
          _memberId = message['memberId'] as String?;
          _roomCode = message['roomCode'] as String?;
          _status = 'Joined family code ${_roomCode ?? '-'}.';
        });
        break;
      case 'room_state':
        final currentId = _memberId ?? '';
        final members = (message['members'] as List<dynamic>)
            .map((entry) => FamilyMember.fromJson(Map<String, dynamic>.from(entry as Map), currentUserId: currentId))
            .toList();
        setState(() {
          _members = members;
          _status = 'Live room synced with ${members.length} member(s).';
        });
        final selected = members.where((member) => member.isCurrentUser && member.location != null).firstOrNull ??
            members.where((member) => member.location != null).firstOrNull;
        if (selected?.location case final location?) {
          _moveMapTo(location.latitude, location.longitude);
        }
        break;
      case 'pong':
        break;
      case 'error':
        setState(() {
          _status = 'Relay error: ${message['message']}';
        });
        break;
    }
  }

  Future<void> _toggleSharing(bool enabled) async {
    setState(() {
      _sharingEnabled = enabled;
    });
    _channel?.sink.add(jsonEncode({'type': 'sharing', 'isSharing': enabled}));
    if (enabled) {
      await _publishCurrentLocation();
    } else {
      setState(() {
        _status = 'Sharing paused on this device.';
      });
    }
  }

  Future<void> _disconnect({bool clearState = true, bool allowReconnect = false}) async {
    _autoReconnectEnabled = allowReconnect;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    await _socketSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _channel?.sink.close();
    _socketSubscription = null;
    _positionSubscription = null;
    _channel = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _isConnected = false;
      _sharingEnabled = false;
      if (clearState) {
        _members = const [];
        _memberId = null;
        _roomCode = null;
        _status = 'Disconnected from relay.';
      }
    });
  }

  void _moveMapTo(double lat, double lng) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _mapController.move(LatLng(lat, lng), 15);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleMembers = _members.where((member) => member.isSharing && member.location != null).toList();
    final initialCenter = visibleMembers.firstOrNull?.location ??
        (_currentPosition == null
            ? const LatLng(37.7749, -122.4194)
            : LatLng(_currentPosition!.latitude, _currentPosition!.longitude));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Locator'),
        actions: [
          if (_isConnected)
            IconButton(
              onPressed: () => _disconnect(),
              icon: const Icon(Icons.link_off),
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visible, consent-based family sharing',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _serverController,
                      decoration: const InputDecoration(
                        labelText: 'Relay URL',
                        hintText: 'ws://10.0.2.2:8080',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Your name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _roomController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Family code',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Everyone must knowingly install the app and join the same family code. This project does not support hidden tracking.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _isJoining ? null : _connectAndJoin,
                          icon: const Icon(Icons.link),
                          label: Text(_isConnected ? 'Reconnect now' : 'Connect & share'),
                        ),
                        if (_isConnected)
                          OutlinedButton.icon(
                            onPressed: () => _toggleSharing(!_sharingEnabled),
                            icon: Icon(_sharingEnabled ? Icons.pause_circle : Icons.play_circle),
                            label: Text(_sharingEnabled ? 'Pause sharing' : 'Resume sharing'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.cloud_done : Icons.cloud_off,
                          color: _isConnected ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_status ?? '')),
                      ],
                    ),
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
                  options: MapOptions(initialCenter: initialCenter, initialZoom: 13),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.family_locator',
                    ),
                    MarkerLayer(
                      markers: visibleMembers.map((member) {
                        final location = member.location!;
                        return Marker(
                          point: location,
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
                        );
                      }).toList(),
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
              itemCount: _members.length,
              itemBuilder: (context, index) {
                final member = _members[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  leading: CircleAvatar(child: Text(member.name.isEmpty ? '?' : member.name.characters.first)),
                  title: Text(member.name),
                  subtitle: Text(
                    '${member.isCurrentUser ? 'You' : 'Family'} • ${member.isSharing ? 'Sharing' : 'Paused'}${member.lastUpdated == null ? '' : ' • ${_formatAgo(member.lastUpdated!)}'}',
                  ),
                  trailing: member.accuracy == null
                      ? null
                      : Text('±${member.accuracy!.round()}m', style: Theme.of(context).textTheme.bodySmall),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 8),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAgo(DateTime timestamp) {
    final delta = DateTime.now().difference(timestamp);
    if (delta.inSeconds < 10) {
      return 'just now';
    }
    if (delta.inMinutes < 1) {
      return '${delta.inSeconds}s ago';
    }
    if (delta.inHours < 1) {
      return '${delta.inMinutes}m ago';
    }
    return '${delta.inHours}h ago';
  }
}
