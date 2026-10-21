import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A road route between two points.
class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  /// Polyline that follows the roads, from start to end.
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  double get distanceKm => distanceMeters / 1000;
  int get durationMinutes => (durationSeconds / 60).ceil();
}

/// Fetches road routes from the public OSRM server (OpenStreetMap data).
///
/// Free, no API key. The public demo server is meant for light use only,
/// so results are cached in memory and each route is requested once.
/// Returns `null` when the route can't be fetched (offline, rate-limited…);
/// callers should fall back to a straight line.
class RouteService {
  RouteService._();

  static const _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  static final Map<String, RoadRoute> _cache = {};
  static final Map<String, Future<RoadRoute?>> _inFlight = {};

  static String _key(LatLng a, LatLng b) =>
      '${a.latitude.toStringAsFixed(5)},${a.longitude.toStringAsFixed(5)};'
      '${b.latitude.toStringAsFixed(5)},${b.longitude.toStringAsFixed(5)}';

  static Future<RoadRoute?> getRoute(LatLng from, LatLng to) {
    final key = _key(from, to);
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    return _inFlight[key] ??= _fetch(from, to, key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  static Future<RoadRoute?> _fetch(LatLng from, LatLng to, String key) async {
    try {
      // OSRM expects longitude,latitude order.
      final uri = Uri.parse(
        '$_baseUrl/${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final resp = await http.get(
        uri,
        headers: kIsWeb
            ? {}
            : {'User-Agent': 'PalengkeGo/1.0 (contact: palengkego@example.com)'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;
      final routes = data['routes'] as List? ?? const [];
      if (routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final coords = (route['geometry']?['coordinates'] as List?) ?? const [];
      final points = coords
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();
      if (points.length < 2) return null;

      final result = RoadRoute(
        points: points,
        distanceMeters: (route['distance'] as num).toDouble(),
        durationSeconds: (route['duration'] as num).toDouble(),
      );
      _cache[key] = result;
      return result;
    } catch (_) {
      return null;
    }
  }
}
