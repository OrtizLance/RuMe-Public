import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;


final Map<String, BitmapDescriptor> _markerIconCache = {};


Future<BitmapDescriptor?> loadCustomMarker(
  String assetPath, {
  int width = 64,
}) async {
  
  if (_markerIconCache.containsKey(assetPath)) {
    return _markerIconCache[assetPath];
  }

  
  try {
    final ByteData data = await rootBundle.load(assetPath);
    final ui.Codec codec =
        await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ByteData? byteData = await fi.image.toByteData(format: ui.ImageByteFormat.png);
    final bitmapDescriptor = BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());

    
    _markerIconCache[assetPath] = bitmapDescriptor;
    return bitmapDescriptor;
  } catch (e) {
    debugPrint("Error loading custom marker from $assetPath: $e");
    return null;
  }
}


Set<Circle> buildRadiusCircle(LatLng center, double radius) {
  return {
    Circle(
      circleId: const CircleId("location_scope"),
      center: center,
      radius: radius,
      fillColor: Colors.blue.withOpacity(0.15),
      strokeColor: Colors.blue,
      strokeWidth: 2,
    ),
  };
}


Widget buildFilterChip({
  required String type,
  required IconData icon,
  required bool selected,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: selected ? Colors.blue : Colors.white,
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : Colors.blue),
            const SizedBox(width: 6),
            Text(
              type.replaceAll("_", " "),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
