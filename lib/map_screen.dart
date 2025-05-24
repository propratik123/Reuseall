import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'short_route_algo.dart';


class MapScreen extends StatefulWidget {
  final List<Map<String, dynamic>> pickupLocations;

  const MapScreen({super.key, required this.pickupLocations});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  LocationData? _currentLocation;
  final Location _location = Location();
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  final String _googleApiKey = "AIzaSyA4RsAyvq-v9HNYWPiBaH7NMWjOpYuBx-Q";
  bool _isLoadingRoute = false;
  String? _routeError;
  StreamSubscription<LocationData>? _locationSubscription;
  
  int _currentOptimizedIndex = 0;
  List<Map<String, dynamic>> _optimizedRoute = [];
  Set<String> _completedPickupIds = {};
  
  String _totalDistance = '';
  String _totalDuration = '';

  @override
  void initState() {
    super.initState();
    _initLocationAndMap();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLocationAndMap() async {
    final hasPermission = await _requestPermission();
    if (!hasPermission) {
      setState(() {
        _routeError = "Location permission denied";
      });
      return;
    }

    try {
      final loc = await _location.getLocation();
      setState(() {
        _currentLocation = loc;
      });

      _calculateOptimalRoute();
      _setMarkers();
      await _drawRoute();
      _startLocationTracking();
    } catch (e) {
      setState(() {
        _routeError = "Error getting location: $e";
      });
    }
  }

  void _startLocationTracking() {
    _locationSubscription = _location.onLocationChanged.listen(
      (LocationData currentLocation) {
        setState(() {
          _currentLocation = currentLocation;
        });
        _updateCurrentLocationMarker();
        _updateRoute();
      },
    );
  }

  void _updateCurrentLocationMarker() {
    if (_currentLocation == null) return;

    _markers.removeWhere((marker) => marker.markerId.value == 'current_location');

    _markers.add(
      Marker(
        markerId: const MarkerId('current_location'),
        position: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
        infoWindow: const InfoWindow(title: 'You (Live)', snippet: 'Delivery Person'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    setState(() {});
  }

  void _updateRoute() async {
    if (_currentLocation == null) return;
    _calculateOptimalRoute();
    await _drawRouteFromCurrentLocation();
  }

  Future<bool> _requestPermission() async {
    final serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled && !(await _location.requestService())) return false;

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return false;
    }

    return true;
  }

  void _calculateOptimalRoute() {
    if (_currentLocation == null) return;

    final remainingPickups = widget.pickupLocations.where((pickup) {
      final pickupId = _getPickupId(pickup);
      return !_completedPickupIds.contains(pickupId);
    }).toList();

    _optimizedRoute = ShortRouteAlgorithm.calculateOptimalRoute(
      currentLat: _currentLocation!.latitude!,
      currentLng: _currentLocation!.longitude!,
      pickupLocations: remainingPickups,
      currentDestinationIndex: 0,
    );

    _currentOptimizedIndex = 0;

    final stats = ShortRouteAlgorithm.calculateRouteStats(
      currentLat: _currentLocation!.latitude!,
      currentLng: _currentLocation!.longitude!,
      optimizedRoute: _optimizedRoute,
    );

    setState(() {
      _totalDistance = stats['totalDistanceKm'];
      _totalDuration = stats['estimatedTime'];
    });
  }

  String _getPickupId(Map<String, dynamic> pickup) {
    return '${pickup['lat']}_${pickup['lng']}';
  }

  String _getPickupStatus(Map<String, dynamic> pickup) {
    final pickupId = _getPickupId(pickup);
    
    if (_completedPickupIds.contains(pickupId)) {
      return 'completed';
    }
    
    final pickupsOnly = _optimizedRoute.where((loc) => loc['type'] != 'warehouse').toList();
    
    for (int i = 0; i < pickupsOnly.length; i++) {
      final routePickupId = _getPickupId(pickupsOnly[i]);
      if (routePickupId == pickupId) {
        if (i == _currentOptimizedIndex) {
          return 'current';
        } else if (i > _currentOptimizedIndex) {
          return 'upcoming';
        }
        break;
      }
    }
    
    return 'upcoming';
  }

  Future<BitmapDescriptor> _createCustomMarker(String type, Map<String, dynamic>? pickup) async {
    double hue;
    
    if (type == 'warehouse') {
      hue = BitmapDescriptor.hueViolet;
    } else if (pickup != null) {
      final status = _getPickupStatus(pickup);
      switch (status) {
        case 'completed':
          hue = BitmapDescriptor.hueGreen;
          break;
        case 'current':
          hue = BitmapDescriptor.hueYellow;
          break;
        case 'upcoming':
          hue = BitmapDescriptor.hueBlue;
          break;
        default:
          hue = BitmapDescriptor.hueBlue;
      }
    } else {
      hue = BitmapDescriptor.hueBlue;
    }
    
    return BitmapDescriptor.defaultMarkerWithHue(hue);
  }

  void _setMarkers() async {
    final markers = <Marker>[];

    for (int i = 0; i < widget.pickupLocations.length; i++) {
      final pickup = widget.pickupLocations[i];
      final status = _getPickupStatus(pickup);
      final BitmapDescriptor customIcon = await _createCustomMarker('pickup', pickup);

      String title;
      String snippet = pickup['address'] ?? 'Pickup Location';
      
      if (status == 'completed') {
        title = 'Pick ${i + 1} ✓';
      } else if (status == 'current') {
        final pickupsOnly = _optimizedRoute.where((loc) => loc['type'] != 'warehouse').toList();
        final optimizedPosition = _currentOptimizedIndex + 1;
        title = 'Pick ${i + 1} (Next #$optimizedPosition)';
      } else {
        final pickupsOnly = _optimizedRoute.where((loc) => loc['type'] != 'warehouse').toList();
        int optimizedPosition = -1;
        final pickupId = _getPickupId(pickup);
        
        for (int j = 0; j < pickupsOnly.length; j++) {
          if (_getPickupId(pickupsOnly[j]) == pickupId) {
            optimizedPosition = j + 1;
            break;
          }
        }
        
        if (optimizedPosition != -1) {
          title = 'Pick ${i + 1} (#$optimizedPosition)';
        } else {
          title = 'Pick ${i + 1}';
        }
      }

      markers.add(
        Marker(
          markerId: MarkerId('pickup_${i}'),
          position: LatLng(pickup['lat'], pickup['lng']),
          infoWindow: InfoWindow(
            title: title,
            snippet: snippet,
          ),
          icon: customIcon,
        ),
      );
    }

    final warehouseIcon = await _createCustomMarker('warehouse', null);
    final warehouse = ShortRouteAlgorithm.getWarehouse();
    markers.add(
      Marker(
        markerId: const MarkerId('warehouse'),
        position: LatLng(warehouse['lat'], warehouse['lng']),
        infoWindow: InfoWindow(
          title: '🏠 ${warehouse['name']}',
          snippet: warehouse['address'],
        ),
        icon: warehouseIcon,
      ),
    );

    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
          infoWindow: const InfoWindow(title: 'You (Live)', snippet: 'Delivery Person'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    setState(() {
      _markers = Set.from(markers);
    });
  }

  Future<void> _drawRoute() async {
    if (widget.pickupLocations.isEmpty) {
      setState(() {
        _routeError = "No pickup locations available";
      });
      return;
    }

    await _drawRouteFromCurrentLocation();
  }

  Future<void> _drawRouteFromCurrentLocation() async {
    if (_currentLocation == null || _optimizedRoute.isEmpty) return;

    setState(() {
      _isLoadingRoute = true;
      _routeError = null;
    });

    try {
      final remainingPickups = _optimizedRoute.where((loc) => loc['type'] != 'warehouse').toList();
      
      if (remainingPickups.isEmpty) {
        final warehouse = ShortRouteAlgorithm.getWarehouse();
        await _drawDirectRoute(
          LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
          LatLng(warehouse['lat'], warehouse['lng']),
        );
        return;
      }

      final origin = '${_currentLocation!.latitude},${_currentLocation!.longitude}';
      final destination = '${_optimizedRoute.last['lat']},${_optimizedRoute.last['lng']}';
      
      String waypointsParam = '';
      if (_optimizedRoute.length > 1) {
        final waypoints = _optimizedRoute
            .sublist(0, _optimizedRoute.length - 1)
            .map((loc) => '${loc['lat']},${loc['lng']}')
            .join('|');
        waypointsParam = '&waypoints=optimize:false|$waypoints';
      }

      final url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination$waypointsParam&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body);

      if (data['status'] != 'OK') {
        throw Exception('API Error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
      }

      if (data['routes'].isEmpty) {
        throw Exception('No routes found');
      }

      final route = data['routes'][0];
      final points = route['overview_polyline']['points'];
      final polylineCoords = _decodePolyline(points);

      final legs = route['legs'] as List;
      int totalDistanceValue = 0;
      int totalDurationValue = 0;
      
      for (final leg in legs) {
        totalDistanceValue += (leg['distance']['value'] as int);
        totalDurationValue += (leg['duration']['value'] as int);
      }

      _totalDistance = '${(totalDistanceValue / 1000).toStringAsFixed(1)} km';
      _totalDuration = '${(totalDurationValue / 60).round()} min';

      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('optimized_route'),
              color: Colors.blue,
              width: 4,
              points: polylineCoords,
              patterns: [],
            ),
          );
          
          _addConnectingLines(_optimizedRoute);
          _isLoadingRoute = false;
        });

        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _fitMapToBounds();
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _routeError = 'Route error: ${e.toString()}';
          _isLoadingRoute = false;
        });
      }
    }
  }

  Future<void> _drawDirectRoute(LatLng origin, LatLng destination) async {
    final url = 'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${origin.latitude},${origin.longitude}&'
        'destination=${destination.latitude},${destination.longitude}&'
        'key=$_googleApiKey';

    try {
      final response = await http.get(Uri.parse(url));
      final data = json.decode(response.body);

      if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
        final route = data['routes'][0];
        final points = route['overview_polyline']['points'];
        final polylineCoords = _decodePolyline(points);

        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('warehouse_route'),
              color: Colors.purple,
              width: 4,
              points: polylineCoords,
            ),
          );
          _isLoadingRoute = false;
        });
      }
    } catch (e) {
      setState(() {
        _routeError = 'Route error: ${e.toString()}';
        _isLoadingRoute = false;
      });
    }
  }

  void _addConnectingLines(List<Map<String, dynamic>> locations) {
    if (locations.length < 2) return;

    final List<LatLng> routePoints = [];
    
    if (_currentLocation != null) {
      routePoints.add(LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!));
    }
    
    for (final location in locations) {
      routePoints.add(LatLng(location['lat'], location['lng']));
    }

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('pickup_sequence'),
        color: Colors.orange,
        width: 2,
        points: routePoints,
        patterns: [PatternItem.dash(10), PatternItem.gap(10)],
      ),
    );
  }

  void _fitMapToBounds() {
    if (_mapController == null) return;

    final List<LatLng> allPoints = [];
    
    if (_currentLocation != null) {
      allPoints.add(LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!));
    }
    
    for (final location in _optimizedRoute) {
      allPoints.add(LatLng(location['lat'], location['lng']));
    }

    if (allPoints.isEmpty) return;

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final point in allPoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        100.0,
      ),
    );
  }

  void _markCurrentDestinationComplete() {
    final pickupsOnly = _optimizedRoute.where((loc) => loc['type'] != 'warehouse').toList();
    
    if (_currentOptimizedIndex < pickupsOnly.length) {
      final currentTarget = pickupsOnly[_currentOptimizedIndex];
      final targetId = _getPickupId(currentTarget);
      
      setState(() {
        _completedPickupIds.add(targetId);
        _currentOptimizedIndex++;
      });
      
      _calculateOptimalRoute();
      _setMarkers();
      _drawRouteFromCurrentLocation();
      
      if (_currentOptimizedIndex < pickupsOnly.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Target completed! Next: Stop ${_currentOptimizedIndex + 1} in optimized route'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All pickups completed! Head to warehouse 🏠'),
            backgroundColor: Colors.purple,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All deliveries completed! 🎉'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return poly;
  }

  String _getNextDestinationText() {
    final pickupsOnly = _optimizedRoute.where((loc) => loc['type'] != 'warehouse').toList();
    
    if (_currentOptimizedIndex < pickupsOnly.length) {
      return 'Next: Stop ${_currentOptimizedIndex + 1} (Optimized Route)';
    } else {
      return 'Next: Warehouse 🏠';
    }
  }

  String _getProgressText() {
    final totalPickups = widget.pickupLocations.length;
    final completedPickups = _completedPickupIds.length;
    
    if (completedPickups < totalPickups) {
      return '$completedPickups/$totalPickups pickups';
    } else {
      return 'Head to warehouse';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "Optimized Delivery Route",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        actions: [
          if (_isLoadingRoute)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getNextDestinationText(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.route, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            _totalDistance.isNotEmpty ? '$_totalDistance • $_totalDuration' : 'Calculating...',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _getProgressText(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_routeError != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _routeError!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _currentLocation == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Getting your location...',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : GoogleMap(
                    onMapCreated: (controller) {
                      _mapController = controller;
                      Future.delayed(const Duration(milliseconds: 800), () {
                        if (mounted) _fitMapToBounds();
                      });
                    },
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                        _currentLocation!.latitude!,
                        _currentLocation!.longitude!,
                      ),
                      zoom: 15,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    markers: _markers,
                    polylines: _polylines,
                    mapType: MapType.normal,
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "center",
            onPressed: () {
              if (_currentLocation != null && _mapController != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: LatLng(
                        _currentLocation!.latitude!,
                        _currentLocation!.longitude!,
                      ),
                      zoom: 15,
                    ),
                  ),
                );
              }
            },
            child: const Icon(Icons.my_location),
            backgroundColor: Colors.white,
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "refresh",
            onPressed: _drawRoute,
            child: const Icon(Icons.refresh),
            tooltip: 'Refresh Route',
          ),
          const SizedBox(height: 8),
          if (_completedPickupIds.length <= widget.pickupLocations.length)
            FloatingActionButton.extended(
              heroTag: "complete",
              onPressed: _markCurrentDestinationComplete,
              icon: const Icon(Icons.check),
              label: Text(_completedPickupIds.length < widget.pickupLocations.length ? 'Complete Target' : 'Complete Delivery'),
              backgroundColor: _completedPickupIds.length < widget.pickupLocations.length ? Colors.green : Colors.purple,
              foregroundColor: Colors.white,
            ),
        ],
      ),
    );
  }
}