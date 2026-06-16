import 'dart:async';
import 'package:nsd/nsd.dart';
import 'package:stealth/local_app_service.dart';

class P2PDiscoveryService {
  final LocalAppService _appService = LocalAppService();
  final String _serviceType = '_stealth-p2p._tcp';

  Registration? _registration;
  Discovery? _discovery;

  final StreamController<Service> _peerController =
      StreamController<Service>.broadcast();
  Stream<Service> get onPeerFound => _peerController.stream;

  Future<void> start() async {
    final myId = await _appService.getUserId();
    if (myId == null) return;

    // Register myself
    _registration = await register(
      Service(name: 'stealth-$myId', type: _serviceType, port: 5555),
    );

    // Start discovery
    _discovery = await startDiscovery(_serviceType);
    _discovery?.addServiceListener((service, status) {
      if (status == ServiceStatus.found) {
        _peerController.add(service);
      }
    });
  }

  Future<void> stop() async {
    if (_registration != null) await unregister(_registration!);
    if (_discovery != null) await stopDiscovery(_discovery!);
    await _peerController.close();
  }
}
