import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

class PlacesApi {
  static const String _placesBaseUrl =
      "https://maps.googleapis.com/maps/api/place/nearbysearch/json";
  static const String _geocodeBaseUrl =
      "https://maps.googleapis.com/maps/api/geocode/json";
  static const String _directionsBaseUrl =
      "https://maps.googleapis.com/maps/api/directions/json";

  static String? _apiKey;

  static Future<void> initialize() async {
    if (_apiKey == null) {
      final contents = await rootBundle.loadString('assets/config.json');
      final config = json.decode(contents);
      _apiKey = config['google_maps_api_key'];
      if (_apiKey == null || _apiKey!.contains("YOUR_") || _apiKey!.isEmpty) {
        
        debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        debugPrint("!!! WARNING: Google Maps API key is not configured. !!!");
        debugPrint("!!! Please add your key to assets/config.json.       !!!");
        debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        
        
      }
    }
  }

  


  
  
  static Future<List<Map<String, dynamic>>> fetchNearbyPlaces({
    required double lat,
    required double lng,
    required String type,
    int radius = 3000, 
  }) async {
    final url = '$_placesBaseUrl?location=$lat,$lng&radius=$radius&type=$type&key=$_apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch nearby places: ${response.body}");
    }

    final data = json.decode(response.body);

    
    if (data["status"] == "ZERO_RESULTS") {
      return [];
    }

    if (data["status"] != "OK") {
      throw Exception("Places API error: ${data["status"]}");
    }

    final results = data["results"] as List<dynamic>;
    return results.map((place) {
      final location = place["geometry"]["location"];
      return {
        "name": place["name"],
        "lat": location["lat"],
        "lng": location["lng"],
        "address": place["vicinity"],
      };
    }).toList();
  }

  
  static Future<Map<String, double>?> geocodeAddress(String address) async {
    final encoded = Uri.encodeComponent(address);
    final url = '$_geocodeBaseUrl?address=$encoded&key=$_apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch geocode: ${response.body}");
    }

    final data = json.decode(response.body);

    if (data["status"] != "OK" || (data["results"] as List).isEmpty) {
      return null; 
    }

    final location = data["results"][0]["geometry"]["location"];
    return {"lat": location["lat"] as double, "lng": location["lng"] as double};
  }

  
  static Future<Map<String, dynamic>?> getRouteInfo({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required String travelMode, 
  }) async {
    final mode = travelMode.toLowerCase();
    final url =
        '$_directionsBaseUrl?origin=$originLat,$originLng&destination=$destLat,$destLng&mode=$mode&key=$_apiKey&region=ph';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch directions: ${response.body}");
    }

    final data = json.decode(response.body);

    if (data["status"] != "OK") return null;

    final leg = data["routes"][0]["legs"][0];
    final overviewPolyline = data["routes"][0]["overview_polyline"]["points"];

    return {
      "distance": leg["distance"]["text"],
      "duration": leg["duration"]["text"],
      "polyline_points": _decodePolyline(overviewPolyline),
    };
  }

  
  static List<Map<String, double>> _decodePolyline(String encoded) {
    List<Map<String, double>> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add({'lat': (lat / 1E5), 'lng': (lng / 1E5)});
    }
    return points;
  }
}
