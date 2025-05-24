import 'dart:math' as math;

class ShortRouteAlgorithm {
  static const Map<String, dynamic> warehouse = {
    "name": "Reuseall Warehouse",
    "address": "213, Anjuman Shopping Complex, Sadar, Nagpur, Maharashtra 440001",
    "lat": 21.1633,
    "lng": 79.0797,
    "type": "warehouse"
  };

  static List<Map<String, dynamic>> calculateOptimalRoute({
    required double currentLat,
    required double currentLng,
    required List<Map<String, dynamic>> pickupLocations,
    required int currentDestinationIndex,
  }) {
    final remainingPickups = pickupLocations.sublist(currentDestinationIndex);
    
    if (remainingPickups.isEmpty) {
      return [warehouse];
    }

    if (remainingPickups.length == 1) {
      return [...remainingPickups, warehouse];
    }

    final nearestFirstRoute = _buildNearestFirstRoute(
      currentLat: currentLat,
      currentLng: currentLng,
      pickups: remainingPickups,
    );

    final optimizedRoute = _improve2OptWithFixedStart(
      route: nearestFirstRoute,
      startLat: currentLat,
      startLng: currentLng,
    );

    return [...optimizedRoute, warehouse];
  }

  static List<Map<String, dynamic>> _buildNearestFirstRoute({
    required double currentLat,
    required double currentLng,
    required List<Map<String, dynamic>> pickups,
  }) {
    if (pickups.isEmpty) return [];

    int nearestIndex = 0;
    double shortestDistance = double.infinity;

    for (int i = 0; i < pickups.length; i++) {
      final distance = _calculateHaversineDistance(
        currentLat,
        currentLng,
        pickups[i]['lat'],
        pickups[i]['lng'],
      );

      if (distance < shortestDistance) {
        shortestDistance = distance;
        nearestIndex = i;
      }
    }

    final route = <Map<String, dynamic>>[];
    final remainingLocations = List<Map<String, dynamic>>.from(pickups);
    
    final nearestPickup = remainingLocations.removeAt(nearestIndex);
    route.add(nearestPickup);

    double currentLatitude = nearestPickup['lat'];
    double currentLongitude = nearestPickup['lng'];

    while (remainingLocations.isNotEmpty) {
      int nextNearestIndex = 0;
      double nextShortestDistance = double.infinity;

      for (int i = 0; i < remainingLocations.length; i++) {
        final distance = _calculateHaversineDistance(
          currentLatitude,
          currentLongitude,
          remainingLocations[i]['lat'],
          remainingLocations[i]['lng'],
        );

        if (distance < nextShortestDistance) {
          nextShortestDistance = distance;
          nextNearestIndex = i;
        }
      }

      final nextLocation = remainingLocations.removeAt(nextNearestIndex);
      route.add(nextLocation);
      
      currentLatitude = nextLocation['lat'];
      currentLongitude = nextLocation['lng'];
    }

    return route;
  }

  static List<Map<String, dynamic>> _improve2OptWithFixedStart({
    required List<Map<String, dynamic>> route,
    required double startLat,
    required double startLng,
  }) {
    if (route.length < 3) return route;

    List<Map<String, dynamic>> bestRoute = List.from(route);
    double bestDistance = _calculateTotalRouteDistance(bestRoute, startLat, startLng);
    bool improved = true;

    while (improved) {
      improved = false;

      for (int i = 1; i < route.length - 1; i++) {
        for (int j = i + 2; j < route.length; j++) {
          final newRoute = _swapEdges(bestRoute, i, j);
          final newDistance = _calculateTotalRouteDistance(newRoute, startLat, startLng);

          if (newDistance < bestDistance) {
            bestRoute = newRoute;
            bestDistance = newDistance;
            improved = true;
          }
        }
      }
    }

    return bestRoute;
  }

  static List<Map<String, dynamic>> _swapEdges(
    List<Map<String, dynamic>> route,
    int i,
    int j,
  ) {
    final newRoute = <Map<String, dynamic>>[];
    
    newRoute.addAll(route.sublist(0, i + 1));
    
    final reversedSegment = route.sublist(i + 1, j + 1).reversed.toList();
    newRoute.addAll(reversedSegment);
    
    newRoute.addAll(route.sublist(j + 1));
    
    return newRoute;
  }

  static double _calculateTotalRouteDistance(
    List<Map<String, dynamic>> route,
    double startLat,
    double startLng,
  ) {
    if (route.isEmpty) return 0.0;

    double totalDistance = 0.0;
    double currentLat = startLat;
    double currentLng = startLng;

    for (final location in route) {
      totalDistance += _calculateHaversineDistance(
        currentLat,
        currentLng,
        location['lat'],
        location['lng'],
      );
      currentLat = location['lat'];
      currentLng = location['lng'];
    }

    totalDistance += _calculateHaversineDistance(
      currentLat,
      currentLng,
      warehouse['lat'],
      warehouse['lng'],
    );

    return totalDistance;
  }

  static Map<String, dynamic>? findNearestPickup({
    required double currentLat,
    required double currentLng,
    required List<Map<String, dynamic>> pickupLocations,
    required int currentDestinationIndex,
  }) {
    final remainingPickups = pickupLocations.sublist(currentDestinationIndex);
    
    if (remainingPickups.isEmpty) return null;

    Map<String, dynamic>? nearestPickup;
    double shortestDistance = double.infinity;

    for (final pickup in remainingPickups) {
      final distance = _calculateHaversineDistance(
        currentLat,
        currentLng,
        pickup['lat'],
        pickup['lng'],
      );

      if (distance < shortestDistance) {
        shortestDistance = distance;
        nearestPickup = pickup;
      }
    }

    return nearestPickup;
  }

  static double _calculateHaversineDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusKm = 6371.0;
    
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    
    final c = 2 * math.asin(math.sqrt(a));
    
    return earthRadiusKm * c;
  }

  static double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  static Map<String, dynamic> getWarehouse() {
    return Map<String, dynamic>.from(warehouse);
  }

  static Map<String, dynamic> calculateRouteStats({
    required double currentLat,
    required double currentLng,
    required List<Map<String, dynamic>> optimizedRoute,
  }) {
    if (optimizedRoute.isEmpty) {
      return {
        'totalDistance': 0.0,
        'totalDistanceKm': '0.0 km',
        'estimatedTime': '0 min',
        'pickupsRemaining': 0,
      };
    }

    final totalDistance = _calculateTotalRouteDistance(
      optimizedRoute.where((loc) => loc['type'] != 'warehouse').toList(),
      currentLat,
      currentLng,
    );

    final estimatedTimeHours = totalDistance / 30.0;
    final estimatedTimeMinutes = (estimatedTimeHours * 60).round();

    final pickupsCount = optimizedRoute.where((loc) => loc['type'] != 'warehouse').length;

    return {
      'totalDistance': totalDistance,
      'totalDistanceKm': '${totalDistance.toStringAsFixed(1)} km',
      'estimatedTime': '$estimatedTimeMinutes min',
      'pickupsRemaining': pickupsCount,
    };
  }
}