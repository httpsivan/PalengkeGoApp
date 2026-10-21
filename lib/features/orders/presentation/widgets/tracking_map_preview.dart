import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:palengkego/core/config/fee_config.dart';
import 'package:palengkego/core/services/route_service.dart';
import 'package:palengkego/core/theme/app_theme.dart';
import 'package:palengkego/features/orders/domain/market_order.dart';
import 'package:palengkego/features/orders/domain/order_status.dart';

class TrackingMapPreview extends StatefulWidget {
  const TrackingMapPreview({super.key, required this.order});

  final MarketOrder order;

  @override
  State<TrackingMapPreview> createState() => _TrackingMapPreviewState();
}

class _TrackingMapPreviewState extends State<TrackingMapPreview> {
  final MapController _mapController = MapController();
  RoadRoute? _roadRoute;
  bool _isLoadingRoute = false;

  static const _marketLocation = LatLng(
    FeeConfig.deliveryOriginLat,
    FeeConfig.deliveryOriginLng,
  );

  @override
  void initState() {
    super.initState();
    _fetchRoadRoute();
  }

  @override
  void didUpdateWidget(covariant TrackingMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.order.deliveryLatitude != oldWidget.order.deliveryLatitude ||
        widget.order.deliveryLongitude != oldWidget.order.deliveryLongitude ||
        widget.order.fulfillmentMethod != oldWidget.order.fulfillmentMethod) {
      _fetchRoadRoute();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchRoadRoute() async {
    final order = widget.order;
    if (order.isPickup) return;

    final lat = order.deliveryLatitude;
    final lng = order.deliveryLongitude;
    if (lat == null || lng == null) return;

    final delivery = LatLng(lat, lng);

    setState(() => _isLoadingRoute = true);
    final route = await RouteService.getRoute(_marketLocation, delivery);
    if (!mounted) return;

    setState(() {
      _roadRoute = route;
      _isLoadingRoute = false;
    });

    _fitMapBounds();
  }

  void _fitMapBounds() {
    final order = widget.order;
    if (order.isPickup) return;

    final lat = order.deliveryLatitude;
    final lng = order.deliveryLongitude;
    if (lat == null || lng == null) return;

    final delivery = LatLng(lat, lng);

    final points = _roadRoute?.points ?? [_marketLocation, delivery];
    if (points.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(points);
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(40, 70, 40, 70),
          maxZoom: 16,
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isPickup = order.isPickup;
    final deliveryLat = order.deliveryLatitude;
    final deliveryLng = order.deliveryLongitude;
    final hasDeliveryCoords = deliveryLat != null && deliveryLng != null;

    final delivery = hasDeliveryCoords ? LatLng(deliveryLat, deliveryLng) : null;
    final showMap = hasDeliveryCoords || isPickup;

    // Road distance or fallback calculation
    String distanceLabel;
    if (isPickup) {
      distanceLabel = '—';
    } else if (_roadRoute != null) {
      distanceLabel = '${_roadRoute!.distanceKm.toStringAsFixed(1)} km';
    } else if (order.deliveryDistanceKm != null) {
      distanceLabel = '${order.deliveryDistanceKm!.toStringAsFixed(1)} km';
    } else if (hasDeliveryCoords) {
      final fee = FeeConfig.computeDeliveryFee(lat: deliveryLat, lng: deliveryLng);
      final km = (fee - FeeConfig.deliveryBaseCharge) / FeeConfig.deliveryPerKm;
      distanceLabel = km > 0 ? '${km.toStringAsFixed(1)} km' : '${fee.toStringAsFixed(0)} km';
      if (km <= 0) distanceLabel = '2.4 km';
    } else {
      distanceLabel = '2.4 km';
    }

    // Dynamic ETA calculation using actual road travel duration
    final etaValue = (() {
      if (order.status == OrderStatus.cancelled || order.status == OrderStatus.rejected) {
        return 'Cancelled';
      }
      if (order.status == OrderStatus.completed) return 'Completed';

      final travelMins = _roadRoute?.durationMinutes ?? 12;

      if (isPickup) {
        if (order.estimatedReadyTime != null) {
          final diff = order.estimatedReadyTime!.difference(DateTime.now()).inMinutes;
          return diff > 0 ? '$diff mins' : 'Ready';
        }
        return 'Ready';
      }

      if (order.status == OrderStatus.outForDelivery) {
        return '~$travelMins mins';
      }

      if (order.status == OrderStatus.ready) {
        return '~$travelMins mins';
      }

      if (order.estimatedReadyTime != null) {
        final prepMins = order.estimatedReadyTime!.difference(DateTime.now()).inMinutes;
        final total = math.max(0, prepMins) + travelMins;
        return '~$total mins';
      }

      return '~${travelMins + 15} mins';
    })();

    // Route points to draw
    final routePoints = _roadRoute?.points ??
        (delivery != null ? [_marketLocation, delivery] : <LatLng>[]);

    return Container(
      height: 290,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            if (showMap)
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: hasDeliveryCoords
                      ? LatLng(
                          (_marketLocation.latitude + delivery!.latitude) / 2,
                          (_marketLocation.longitude + delivery.longitude) / 2,
                        )
                      : _marketLocation,
                  initialZoom: hasDeliveryCoords ? 13 : 15,
                  onMapReady: _fitMapBounds,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    fallbackUrl:
                        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                    userAgentPackageName: 'com.palengkego.app',
                    panBuffer: 0,
                    keepBuffer: 3,
                    tileBuilder: (context, tileWidget, tile) {
                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: tile.loadError ? 0.3 : 1.0,
                        child: tileWidget,
                      );
                    },
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        '© OpenStreetMap contributors',
                        onTap: () {},
                      ),
                    ],
                  ),
                  if (!isPickup && routePoints.isNotEmpty) ...[
                    // Polyline casing / shadow
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routePoints,
                          strokeWidth: 7,
                          color: AppTheme.primaryGreen.withValues(alpha: 0.25),
                        ),
                        // Main road route polyline
                        Polyline(
                          points: routePoints,
                          strokeWidth: 4.5,
                          color: AppTheme.primaryGreen,
                        ),
                      ],
                    ),
                  ],
                  MarkerLayer(
                    markers: [
                      // Market location pin
                      Marker(
                        point: _marketLocation,
                        width: 44,
                        height: 44,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.primaryGreen, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          child: const Icon(
                            Icons.store_rounded,
                            color: AppTheme.primaryGreen,
                            size: 22,
                          ),
                        ),
                      ),
                      // Delivery destination pin
                      if (!isPickup && delivery != null)
                        Marker(
                          point: delivery,
                          width: 44,
                          height: 44,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFD97706), width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Color(0xFFD97706),
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFD9FBE6), Color(0xFFE9F7EF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: CustomPaint(
                  painter: _MapGridPainter(),
                  child: const SizedBox.expand(),
                ),
              ),

            // Top Left Badge: Estimated Arrival
            Positioned(
              top: 12,
              left: 12,
              child: _MapBadge(
                label: isPickup ? 'ESTIMATED READY TIME' : 'ESTIMATED ARRIVAL',
                value: etaValue,
                trailing: _isLoadingRoute
                    ? const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      )
                    : null,
              ),
            ),

            // Top Right Badge: Distance
            if (!isPickup)
              Positioned(
                top: 12,
                right: 12,
                child: _MapBadge(label: 'ROAD DISTANCE', value: distanceLabel),
              ),

            // Re-center / Fit bounds button
            if (showMap && !isPickup)
              Positioned(
                bottom: 54,
                right: 12,
                child: Material(
                  elevation: 3,
                  shape: const CircleBorder(),
                  color: Colors.white,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _fitMapBounds,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.crop_free_rounded,
                        size: 20,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                ),
              ),

            if (isPickup)
              Positioned(
                top: 100,
                right: 80,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'STALL 12',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // Bottom Route Summary Bar
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 4),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.route_rounded, size: 16, color: AppTheme.primaryGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasDeliveryCoords
                            ? 'Market → Delivery • ${order.deliveryAddress ?? ''}'
                            : 'Market: Naga City People\'s Mall, Abella',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapBadge extends StatelessWidget {
  const _MapBadge({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryGreen,
                ),
              ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBBF7D0)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
