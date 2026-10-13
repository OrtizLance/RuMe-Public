import 'dart:ui' as ui;
import 'dart:math';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:iconsax/iconsax.dart';
import 'package:rume/components/loading_screen.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:rume/seeker_module/properties/property_rooms_page.dart';
import 'package:rume/components/app_colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:rume/seeker_module/property_search/places_API/places_api.dart';
import 'package:rume/seeker_module/property_search/property_search_helpers.dart';

class PropertySearchPage extends StatefulWidget {
  const PropertySearchPage({super.key});

  @override
  State<PropertySearchPage> createState() => _PropertySearchPageState();
}

class _PropertySearchPageState extends State<PropertySearchPage> {
  GoogleMapController? mapController;

  final Set<Marker> _propertyMarkers = {};
  final Set<Marker> _poiMarkers = {};
  List<QueryDocumentSnapshot> _allProperties = [];
  final Set<Polyline> _polylines = {};

  Map<String, dynamic>? _selectedProperty;
  LatLng? _currentLocation;

  final TextEditingController _searchController = TextEditingController();
  LatLng? _selectedPoiLocation;

  BitmapDescriptor? _customMarkerIcon;
  BitmapDescriptor? _myLocationMarkerIcon;
  final Map<String, BitmapDescriptor> _filterIcons = {};
  final Set<String> _activePoiTypes = {};
  Map<String, dynamic>? _selectedPoiInfo;

  List<dynamic> _cities = [];
  List<dynamic> _barangays = [];
  String? _selectedCity;
  String? _selectedBarangay;
  final Set<Circle> _circles = {};

  double _searchRadius = 2000; 

  LatLng? _selectedMarkerPos;
  RangeValues _priceRange = const RangeValues(0, 50000);

  bool _isSearching = false;
  bool _isBookmarked = false;
  
  List<String> _searchSuggestions = [];
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    mapController?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final dataFetchFuture = () async {
      _customMarkerIcon = await loadCustomMarker(
        "assets/images/icons/home_marker.png",
        width: 150,
      );
      _myLocationMarkerIcon = await loadCustomMarker(
        "assets/images/icons/my_location.png",
        width: 140,
      );
      await _loadFilterIcons();
      await _getCurrentLocation();
      await _fetchAndSetPropertyMarkers();
      await _loadAddresses();
    }();

    await Future.wait([
      dataFetchFuture,
      Future.delayed(const Duration(seconds: 1)),
    ]);
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  Future<void> _loadAddresses() async {
    final jsonString = await rootBundle.loadString("assets/ph_address.json");
    final data = json.decode(jsonString);
    if (!mounted) return;
    setState(() {
      _cities = data["cities"] ?? [];
    });
  }

  Future<void> _loadFilterIcons() async {
    final iconsToLoad = {
      "school": "assets/images/icons/map-marker.png",
      "restaurant": "assets/images/icons/restaurant.png",
      "cafe": "assets/images/icons/coffee-shop.png",
      "pharmacy": "assets/images/icons/pharmacy.png",
      "laundry": "assets/images/icons/t-shirt.png",
      "convenience_store": "assets/images/icons/shop.png",
      "transit_station": "assets/images/icons/bus-stop.png",
      "hospital": "assets/images/icons/hospital.png",
      "lodging": "assets/images/icons/hotel.png",
      "park": "assets/images/icons/green-areas.png",
      "church": "assets/images/icons/christian.png",
      "gas_station": "assets/images/icons/gas-station.png",
      "atm": "assets/images/icons/atm.png",
      "shopping_mall": "assets/images/icons/location.png",
    };

    for (var entry in iconsToLoad.entries) {
      try {
        final data = await rootBundle.load(entry.value);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetWidth: 80,
        );
        final fi = await codec.getNextFrame();
        final byteData = await fi.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        _filterIcons[entry.key] = BitmapDescriptor.fromBytes(
          byteData!.buffer.asUint8List(),
        );
      } catch (e) {
        debugPrint("⚠️ Could not load icon for ${entry.key}: $e");
      }
    }

    if (mounted) setState(() {});
  }

  
  void _updateMapCenter(LatLng newCenter) {
    setState(() {
      _currentLocation = newCenter;

      
      _circles
        ..clear()
        ..addAll(buildRadiusCircle(_currentLocation!, _searchRadius));

      
      _propertyMarkers.removeWhere((m) => m.markerId.value == 'my_location');
      _propertyMarkers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: newCenter,
          icon: _myLocationMarkerIcon ?? BitmapDescriptor.defaultMarker,
          zIndex: 1, 
        ),
      );
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always)
          return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      _updateMapCenter(LatLng(position.latitude, position.longitude));
      _filterAndSetMarkers();
      await _refreshPois();
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  Future<void> _fetchAndSetPropertyMarkers() async {
    try {
      final properties = await FirebaseFirestore.instance
          .collection('properties')
          .where('status', isEqualTo: 'verified')
          .get();
      _allProperties = properties.docs;
      _filterAndSetMarkers();
    } catch (e) {
      debugPrint("❌ Error fetching properties: $e");
    }
  }

  
  Future<void> _recordTap(DocumentReference docRef) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; 

    try {
      
      
      await docRef.update({'viewedBy.${user.uid}': true});
    } catch (e) {
      debugPrint("Error recording tap: $e");
    }
  }

  Future<void> _checkIfBookmarked(String propertyId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isBookmarked = false);
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('bookmarks')
        .doc(propertyId)
        .get();

    if (mounted) {
      setState(() => _isBookmarked = doc.exists);
    }
  }

  Future<void> _toggleBookmark(String propertyId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to bookmark properties.'),
        ),
      );
      return;
    }

    final bookmarkRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('bookmarks')
        .doc(propertyId);

    if (_isBookmarked) {
      await bookmarkRef.delete();
    } else {
      await bookmarkRef.set({'bookmarkedAt': FieldValue.serverTimestamp()});
    }
    _checkIfBookmarked(propertyId); 
  }

  Future<void> _filterAndSetMarkers() async {
    
    if (_currentLocation == null) return;

    final Set<Marker> newMarkers = {};
    for (var doc in _allProperties) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['location'] == null) continue;

      final GeoPoint location = data['location'];
      final LatLng position = LatLng(location.latitude, location.longitude);

      final distance = Geolocator.distanceBetween(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
        position.latitude,
        position.longitude,
      );

      if (distance <= _searchRadius) {
        
        final roomsSnapshot = await doc.reference
            .collection('rooms')
            .where('price', isGreaterThanOrEqualTo: _priceRange.start)
            .where('price', isLessThanOrEqualTo: _priceRange.end)
            .where('status', isEqualTo: 'available')
            .limit(1)
            .get();

        
        
        if (roomsSnapshot.docs.isEmpty && _priceRange.end < 50000) {
          continue;
        }

        
        final viewedBy = data['viewedBy'] as Map<String, dynamic>? ?? {};
        final totalViews = viewedBy.length;
        final averageRating =
            (data['averageRating'] as num?)?.toDouble() ?? 0.0;
        final ratingCount = data['ratingCount'] as int? ?? 0;

        newMarkers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: position,
            icon: _customMarkerIcon ?? BitmapDescriptor.defaultMarker,
            onTap: () async {
              if (!mounted) return;
              setState(() {
                _selectedProperty = {
                  "id": doc.id,
                  "name": data['name'] ?? "Unnamed Property",
                  "address": data['address'] ?? "No address",
                  "location": position,
                  "backgroundImage": data['backgroundImageUrl'],
                  "totalViews": totalViews, 
                  "averageRating": averageRating,
                  "ratingCount": ratingCount,
                };
                _selectedMarkerPos = position;
                _checkIfBookmarked(doc.id);
              });
            },
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      
      final myLocationMarker = _propertyMarkers.firstWhere(
        (m) => m.markerId.value == 'my_location',
        orElse: () => const Marker(markerId: MarkerId('')), 
      );

      _propertyMarkers
        ..clear()
        ..addAll(newMarkers);
      if (myLocationMarker.markerId.value.isNotEmpty) {
        _propertyMarkers.add(myLocationMarker);
      }
    });
  }

  Future<void> _searchBoardingHouses(String query) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _selectedProperty = null; 
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'searchProperties',
      );
      final response = await callable.call({'query': query});

      final rawResults = response.data as List<dynamic>? ?? [];
      final results = rawResults
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final Set<Marker> newMarkers = {};
      for (var property in results) {
        if (property['location'] == null) continue;

        final LatLng position = LatLng(
          property['location']['lat'],
          property['location']['lng'],
        );

        newMarkers.add(
          Marker(
            markerId: MarkerId("property_${property['id']}"),
            position: position,
            icon: _customMarkerIcon ?? BitmapDescriptor.defaultMarker,
            onTap: () {
              if (!mounted) return;
              setState(() {
                _selectedProperty = {
                  "id": property['id'],
                  "name": property['name'],
                  "address": property['address'],
                  "location": position,
                  "backgroundImage": property['backgroundImageUrl'],
                  "totalViews": 0, 
                  "averageRating":
                      (property['averageRating'] as num?)?.toDouble() ?? 0.0,
                  "ratingCount": property['ratingCount'] as int? ?? 0,
                };
                _selectedMarkerPos = position;
                _checkIfBookmarked(property['id']);
              });
            },
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        
        final myLocationMarker = _propertyMarkers.firstWhere(
          (m) => m.markerId.value == 'my_location',
          orElse: () =>
              const Marker(markerId: MarkerId('')), 
        );

        _propertyMarkers
          ..clear()
          ..addAll(newMarkers);
        if (myLocationMarker.markerId.value.isNotEmpty) {
          _propertyMarkers.add(myLocationMarker);
        }
        _selectedProperty = null;
      });
    } catch (e) {
      debugPrint("❌ Error calling searchProperties: $e");
      if (mounted) _fetchAndSetPropertyMarkers();
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  
  void _getSearchSuggestions(String query) {
    if (query.isEmpty) {
      if (mounted) setState(() => _searchSuggestions = []);
      return;
    }

    final lowerCaseQuery = query.toLowerCase();
    final Set<String> suggestions = {};

    
    for (final property in _allProperties) {
      final propertyName =
          (property.data() as Map<String, dynamic>)['name'] as String? ?? '';
      if (propertyName.toLowerCase().contains(lowerCaseQuery)) {
        suggestions.add(propertyName);
      }
    }

    
    const commonAmenities = [
      'Wifi',
      'Aircon',
      'Parking',
      'Private CR',
      'Kitchen',
    ];
    for (final amenity in commonAmenities) {
      if (amenity.toLowerCase().contains(lowerCaseQuery)) {
        suggestions.add('Room with $amenity');
      }
    }

    
    if ('under'.contains(lowerCaseQuery) || 'cheap'.contains(lowerCaseQuery)) {
      suggestions.add('Rooms under ₱3000');
      suggestions.add('Rooms under ₱5000');
    }

    
    if ('for 2'.contains(lowerCaseQuery) ||
        'good for 2'.contains(lowerCaseQuery)) {
      suggestions.add('Room for 2 people');
    }

    if (mounted) setState(() => _searchSuggestions = suggestions.toList());
  }

  Future<void> _searchLocation(String query) async {
    final coords = await PlacesApi.geocodeAddress(query);
    if (coords == null) return;

    final target = LatLng(coords["lat"]!, coords["lng"]!);

    if (!mounted) return;

    _updateMapCenter(target);
    _filterAndSetMarkers();

    if (mapController != null) {
      final southwest = LatLng(
        target.latitude - _searchRadius / 111000,
        target.longitude -
            _searchRadius / (111000 * cos(target.latitude * pi / 180)),
      );
      final northeast = LatLng(
        target.latitude + _searchRadius / 111000,
        target.longitude +
            _searchRadius / (111000 * cos(target.latitude * pi / 180)),
      );

      mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: southwest, northeast: northeast),
          50,
        ),
      );
    }

    await _refreshPois();
  }

  
  Future<void> _refreshPois() async {
    if (_currentLocation == null) return;
    if (_activePoiTypes.isEmpty) {
      setState(() => _poiMarkers.clear());
      return;
    }

    final activeTypes = List<String>.from(_activePoiTypes); 
    final Set<Marker> newPoiMarkers = {};

    for (var type in activeTypes) {
      final places = await PlacesApi.fetchNearbyPlaces(
        lat: _currentLocation!.latitude,
        lng: _currentLocation!.longitude,
        type: type,
        radius: _searchRadius.toInt(),
      );

      final markers = places.map((place) {
        final pos = LatLng(place["lat"], place["lng"]);
        return Marker(
          markerId: MarkerId("poi_${type}_${place["name"]}_${place["lat"]}"),
          position: pos,
          icon:
              _filterIcons[type] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          onTap: () => _onPoiTapped(pos, place["name"]),
        );
      }).toSet();

      newPoiMarkers.addAll(markers);
    }

    if (!mounted) return;
    setState(() {
      _poiMarkers
        ..clear()
        ..addAll(newPoiMarkers);
    });
  }

  Future<void> _onPoiTapped(LatLng poiPosition, String poiName) async {
    if (_currentLocation == null) return;

    
    final results = await Future.wait([
      PlacesApi.getRouteInfo(
        originLat: _currentLocation!.latitude,
        originLng: _currentLocation!.longitude,
        destLat: poiPosition.latitude,
        destLng: poiPosition.longitude,
        travelMode: 'driving',
      ),
      PlacesApi.getRouteInfo(
        originLat: _currentLocation!.latitude,
        originLng: _currentLocation!.longitude,
        destLat: poiPosition.latitude,
        destLng: poiPosition.longitude,
        travelMode: 'walking',
      ),
      PlacesApi.getRouteInfo(
        originLat: _currentLocation!.latitude,
        originLng: _currentLocation!.longitude,
        destLat: poiPosition.latitude,
        destLng: poiPosition.longitude,
        travelMode: 'transit',
      ),
    ]);

    final driveInfo = results[0];
    final walkInfo = results[1];
    final transitInfo = results[2];

    
    Polyline? routePolyline;
    if (driveInfo != null) {
      final polylinePoints =
          driveInfo['polyline_points'] as List<dynamic>? ?? [];
      final List<LatLng> points =
          polylinePoints.map((p) => LatLng(p['lat'], p['lng'])).toList();
      routePolyline = Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: Colors.blueAccent,
        width: 5,
      );
    }

    if (mounted) {
      setState(() {
        _selectedPoiInfo = {
          "name": poiName,
          "drive": driveInfo,
          "walk": walkInfo,
          "transit": transitInfo,
        };
        _selectedPoiLocation = poiPosition;
        _polylines..clear()..add(routePolyline!);
      });
    }
  }

  
  Future<void> _updatePolyline() async {
    if (_selectedPoiLocation == null || _currentLocation == null) {
      return; 
    }

    final info = await PlacesApi.getRouteInfo(
      originLat: _currentLocation!.latitude,
      originLng: _currentLocation!.longitude,
      destLat: _selectedPoiLocation!.latitude,
      destLng: _selectedPoiLocation!.longitude,
      travelMode: 'DRIVE', 
    );

    if (info != null && mounted) {
      final polylinePoints = info['polyline_points'] as List<dynamic>? ?? [];
      final List<LatLng> points = polylinePoints
          .map((point) => LatLng(point['lat'], point['lng']))
          .toList();

      final polyline = Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: Colors.blueAccent,
        width: 5,
      );

      setState(() {
        
        _selectedPoiInfo?['distance'] = info['distance'];
        _selectedPoiInfo?['duration'] = info['duration'];
        _polylines.clear();
        _polylines.add(polyline);
      });
    }
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Filter Options",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 20),

                  
                  const Text(
                    "Location",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderGray),
                    ),
                    child: DropdownButton<String>(
                      hint: const Text(
                        "Select City",
                        style: TextStyle(color: AppColors.textGray),
                      ),
                      value: _selectedCity,
                      isExpanded: true,
                      underline:
                          const SizedBox(), 
                      items: _cities.map<DropdownMenuItem<String>>((city) {
                        return DropdownMenuItem<String>(
                          value: city["name"],
                          child: Text(city["name"]),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setModalState(() {
                          _selectedCity = val;
                          _barangays =
                              (_cities.firstWhere(
                                    (c) => c["name"] == val,
                                  )["barangays"])
                                  as List<dynamic>;
                          _selectedBarangay = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderGray),
                    ),
                    child: DropdownButton<String>(
                      hint: const Text(
                        "Select Barangay",
                        style: TextStyle(color: AppColors.textGray),
                      ),
                      value: _selectedBarangay,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: _barangays.map<DropdownMenuItem<String>>((brgy) {
                        return DropdownMenuItem<String>(
                          value: brgy,
                          child: Text(brgy),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setModalState(() => _selectedBarangay = val),
                    ),
                  ),
                  const SizedBox(height: 20),

                  
                  const Text(
                    "Price Range",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  RangeSlider(
                    values: _priceRange,
                    min: 0,
                    max: 50000,
                    divisions: 50,
                    activeColor: AppColors.primary,
                    inactiveColor: AppColors.primaryIndigoLight,
                    labels: RangeLabels(
                      '₱${_priceRange.start.round()}',
                      '₱${_priceRange.end.round()}',
                    ),
                    onChanged: (values) {
                      setModalState(() => _priceRange = values);
                    },
                  ),
                  const SizedBox(height: 20),

                  
                  Text(
                    "Search Radius: ${(_searchRadius / 1000).toStringAsFixed(1)} km",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Slider(
                    min: 500,
                    max: 10000,
                    divisions: 19,
                    value: _searchRadius,
                    activeColor: AppColors.primary,
                    inactiveColor: AppColors.primaryIndigoLight,
                    onChanged: (val) {
                      setModalState(() => _searchRadius = val);
                    },
                  ),
                  const SizedBox(height: 30),

                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              _selectedCity = null;
                              _selectedBarangay = null;
                              _barangays = [];
                              _priceRange = const RangeValues(0, 50000);
                              _searchRadius = 2000;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Reset',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(context); 

                            if (_selectedCity != null) {
                              final fullAddress = _selectedBarangay != null
                                  ? "$_selectedBarangay, $_selectedCity, Philippines"
                                  : "$_selectedCity, Philippines";
                              await _searchLocation(fullAddress);
                            } else if (_currentLocation != null) {
                              
                              _updateMapCenter(_currentLocation!);
                              _filterAndSetMarkers();
                              _refreshPois();
                            }
                          },
                          child: const Text(
                            "Apply",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentLocation == null) {
      return const StandardLoadingScreen();
    }

    final allMarkers = {
      ..._propertyMarkers,
      ..._poiMarkers,
    }; 

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            onTap: (_) => setState(() {
              _selectedProperty = null;
              _selectedMarkerPos = null; 
              _polylines.clear();
              _selectedPoiInfo = null;
              _selectedPoiLocation = null;
            }),

            mapType: MapType.hybrid,
            initialCameraPosition: CameraPosition(
              target: _currentLocation!,
              zoom: 15.5,
            ),
            markers: allMarkers,
            polylines: _polylines,
            circles: _circles,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            myLocationEnabled: false, 
          ),

          if (_selectedPoiInfo != null) _buildPoiInfoCard(),

          
          Positioned(
            bottom: 10,
            right: 10,

            child: Center(
              child: GestureDetector(
                onTap: () async {
                  if (mapController != null) {
                    try {
                      LocationPermission permission =
                          await Geolocator.checkPermission();
                      if (permission == LocationPermission.denied) {
                        permission = await Geolocator.requestPermission();
                      }
                      if (permission == LocationPermission.deniedForever ||
                          permission == LocationPermission.denied) {
                        throw Exception("Location permission denied");
                      }

                      final pos = await Geolocator.getCurrentPosition(
                        desiredAccuracy: LocationAccuracy.high,
                      );

                      mapController!.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: LatLng(pos.latitude, pos.longitude),
                            zoom: 16.5,
                          ),
                        ),
                      );
                      if (mounted) {
                        _updateMapCenter(LatLng(pos.latitude, pos.longitude));
                        _filterAndSetMarkers();
                        await _refreshPois(); 
                      }
                    } catch (e) {
                      debugPrint("Error fetching location: $e");
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(1, 0, 1, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Symbols.home_pin, 
                          size: 45,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "My Location",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          
          if (_selectedProperty != null && _selectedMarkerPos != null)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isSmallScreen = constraints.maxWidth < 380;
                  final cardWidth = isSmallScreen
                      ? constraints.maxWidth * 0.7
                      : 290.0;
                  final buttonSize = isSmallScreen ? 90.0 : 98.0;

                  return Stack(
                    children: [
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: isSmallScreen ? 0 : 0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      minimumSize: Size(10, buttonSize),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 12,
                                      ),
                                    ),
                                    onPressed: () async {
                                      _updateMapCenter(_selectedMarkerPos!);
                                      _filterAndSetMarkers();
                                      _refreshPois();
                                      _updatePolyline();
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Iconsax.location,
                                          size: isSmallScreen ? 30 : 45,
                                          color: Colors.white,
                                        ),
                                        SizedBox(height: isSmallScreen ? 4 : 8),
                                        Text(
                                          "Set location",
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 12 : 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isBookmarked
                                          ? Colors.pinkAccent
                                          : Colors.white,
                                      foregroundColor: _isBookmarked
                                          ? Colors.white
                                          : Colors.pinkAccent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      minimumSize: Size(95, buttonSize),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 16,
                                      ),
                                    ),
                                    onPressed: () => _toggleBookmark(
                                      _selectedProperty!['id'],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _isBookmarked
                                              ? Iconsax.archive_tick4
                                              : Iconsax.archive_add,
                                          size: isSmallScreen ? 30 : 45,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          _isBookmarked ? "Saved" : "Bookmark",
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 12 : 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 3),
                            SizedBox(
                              width: cardWidth,
                              height: 180,
                              child: GestureDetector(
                                onTap: () {
                                  
                                  _recordTap(
                                    FirebaseFirestore.instance
                                        .collection('properties')
                                        .doc(_selectedProperty!["id"]),
                                  );
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PropertyRoomsPage(
                                        propertyId: _selectedProperty!["id"],
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  height: 180,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      20,
                                    ), 
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                    image:
                                        _selectedProperty!["backgroundImage"] !=
                                            null
                                        ? DecorationImage(
                                            image: CachedNetworkImageProvider(
                                              _selectedProperty!["backgroundImage"],
                                            ),
                                            fit: BoxFit.cover,
                                          )
                                        : const DecorationImage(
                                            image: AssetImage(
                                              "assets/images/placeholder.png",
                                            ),
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: Colors.black.withOpacity(0.4),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _selectedProperty!["name"] ??
                                                    "Unnamed",
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                _selectedProperty!["address"] ??
                                                    "No address",
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              if ((_selectedProperty!["ratingCount"] ??
                                                      0) >
                                                  0)
                                                _buildRatingStars(
                                                  _selectedProperty!["averageRating"] ??
                                                      0.0,
                                                  _selectedProperty!["ratingCount"] ??
                                                      0,
                                                )
                                              else
                                                const Text(
                                                  'No reviews yet',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              const Spacer(),
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.visibility,
                                                    color: Colors.white70,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '${_selectedProperty!["totalViews"] ?? 0} views',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

          
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 15,
            right: 15,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _getSearchSuggestions,
                          onSubmitted: _searchBoardingHouses,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            hintText:
                                'Search for boarding houses or a location...',
                            border: InputBorder.none,
                            icon: Icon(Icons.search, color: AppColors.primary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _showFilterOptions,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Icon(Icons.tune, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                
                if (_searchSuggestions.isNotEmpty && _searchFocusNode.hasFocus)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchSuggestions.length > 5
                          ? 5
                          : _searchSuggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _searchSuggestions[index];
                        return ListTile(
                          leading: const Icon(
                            Iconsax.search_normal_1,
                            color: AppColors.textGray,
                          ),
                          title: Text(suggestion),
                          onTap: () {
                            _searchController.text = suggestion;
                            _searchFocusNode.unfocus();
                            _searchBoardingHouses(suggestion);
                            setState(() => _searchSuggestions = []);
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      
                      _buildFilterChip("school", Iconsax.teacher),
                      _buildFilterChip("restaurant", Iconsax.reserve),
                      _buildFilterChip("hospital", Iconsax.hospital),
                      _buildFilterChip("pharmacy", Iconsax.health),
                      _buildFilterChip("transit_station", Iconsax.bus),
                      _buildFilterChip("park", Iconsax.tree),
                      _buildFilterChip("church", Iconsax.building_3),
                      _buildFilterChip("gas_station", Iconsax.gas_station),
                      _buildFilterChip("atm", Iconsax.card),
                      _buildFilterChip("shopping_mall", Iconsax.bag_2),
                      _buildFilterChip("convenience_store", Iconsax.shop),
                      _buildFilterChip("lodging", Iconsax.building),
                      _buildFilterChip("cafe", Iconsax.coffee),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          if (_isSearching)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        "Searching for your ideal place...",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPoiInfoCard() {
    final poiName = _selectedPoiInfo!['name'] as String? ?? 'Point of Interest';
    final driveInfo =
        _selectedPoiInfo!['drive'] as Map<String, dynamic>?;
    final walkInfo = _selectedPoiInfo!['walk'] as Map<String, dynamic>?;
    final transitInfo =
        _selectedPoiInfo!['transit'] as Map<String, dynamic>?;

    return Positioned(
      bottom: 515,
      left: 15,
      right: 15,

      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 5, 15, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    poiName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => setState(() {
                    _selectedPoiInfo = null;
                    _polylines.clear();
                    _selectedPoiLocation = null;
                  }),
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 15,),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTravelModeInfo(
                  icon: Iconsax.car,
                  info: driveInfo,
                ),
                _buildTravelModeInfo(
                  icon: Symbols.steps,
                  info: walkInfo,
                ),
                _buildTravelModeInfo(
                  icon: Iconsax.bus,
                  info: transitInfo,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTravelModeInfo({
    required IconData icon,
    required Map<String, dynamic>? info,
  }) {
    final duration = info?['duration'] as String? ?? '--';
    final distance = info?['distance'] as String? ?? '--';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primary, size: 28),
        const SizedBox(height: 8),
        Text(
          duration,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          distance,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
            fontFamily: 'Roboto',
          ),
        ),
      ],
    );
  }

  
  
  Widget _buildFilterChip(String type, IconData icon) {
    final bool selected = _activePoiTypes.contains(type);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () async {
          setState(() {
            if (selected) {
              _activePoiTypes.remove(type);
            } else {
              if (_activePoiTypes.length < 5) {
                _activePoiTypes.add(type);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'You can only select up to 5 filters at a time.',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          });
          await _refreshPois();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: selected ? Colors.blueAccent : Colors.white,
            border: Border.all(
              color: selected ? Colors.blueAccent : Colors.grey.shade300,
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
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.blueAccent,
              ),
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

  Widget _buildRatingStars(double rating, int reviewCount) {
    List<Widget> stars = [];
    int fullStars = rating.floor();
    bool hasHalfStar = (rating - fullStars) >= 0.5;

    
    for (int i = 0; i < fullStars; i++) {
      stars.add(const Icon(Icons.star, color: Colors.amber, size: 18));
    }

    
    if (hasHalfStar) {
      stars.add(const Icon(Icons.star_half, color: Colors.amber, size: 18));
    }

    
    int emptyStars = 5 - stars.length;
    for (int i = 0; i < emptyStars; i++) {
      stars.add(const Icon(Icons.star_border, color: Colors.amber, size: 18));
    }

    return Row(
      children: [
        ...stars,
        const SizedBox(width: 6),
        Text(
          '${rating.toStringAsFixed(1)} ($reviewCount)',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
