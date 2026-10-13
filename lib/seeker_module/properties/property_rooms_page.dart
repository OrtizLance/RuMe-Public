
import 'dart:async'; 
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/seeker_module/inquiries/s_dialog_inquiry.dart';
import 'package:rume/seeker_module/inquiries/seeker_chat.dart';
import 'package:rume/seeker_module/properties/seeker_room_details.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rume/seeker_module/property_search/property_search_helpers.dart';
import 'package:confetti/confetti.dart'; 


class PropertyRoomsPage extends StatefulWidget {
  final String propertyId;

  const PropertyRoomsPage({super.key, required this.propertyId});

  @override
  State<PropertyRoomsPage> createState() => _PropertyRoomsPageState();
}

class _PropertyRoomsPageState extends State<PropertyRoomsPage> {
  
  late ConfettiController _confettiController;
  RangeValues _capacityRange = const RangeValues(1, 10);
  RangeValues _priceRange = const RangeValues(0, 10000);
  Map<String, bool> _selectedAmenities = {};
  List<DocumentSnapshot> _allRooms = [];
  List<DocumentSnapshot> _filteredRooms = [];
  Map<String, List<String>> _amenities = {};
  BitmapDescriptor? _customMarkerIcon;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 1),
    );
    _loadAmenities();
    _initMarker();
  }

  Future<void> _initMarker() async {
    _customMarkerIcon = await loadCustomMarker(
      'assets/images/icons/home_marker.png',
      width: 150,
    );
    if (mounted) setState(() {});
  }

  Future<void> _loadAmenities() async {
    final String response = await rootBundle.loadString(
      'assets/amenities.json',
    );
    final data = await json.decode(response);
    setState(() {
      _amenities = (data['amenities'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          (value as List<dynamic>).map((e) => e.toString()).toList(),
        ),
      );
    });
  }

  @override
  void dispose() {
    
    _confettiController.dispose();
    super.dispose();
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Text(
                    'Filter Rooms',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCapacityFilter(setModalState),
                          const SizedBox(height: 24),
                          _buildPriceFilter(setModalState),
                          const SizedBox(height: 24),
                          _buildAmenitiesFilter(setModalState),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              _capacityRange = const RangeValues(1, 10);
                              _priceRange = const RangeValues(0, 10000);
                              _selectedAmenities.clear();
                            });
                            _applyFilters();
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
                          onPressed: () {
                            _applyFilters();
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Apply',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _applyFilters() {
    setState(() {
      _filteredRooms = _allRooms.where((room) {
        final data = room.data() as Map<String, dynamic>;
        final capacity = data['capacity'] ?? 1;
        final price = data['price'] ?? 0;
        final amenities = List<String>.from(data['amenities'] ?? []);

        final capacityFilter =
            capacity >= _capacityRange.start && capacity <= _capacityRange.end;
        final priceFilter =
            price >= _priceRange.start && price <= _priceRange.end;
        final amenitiesFilter = _selectedAmenities.entries.every((entry) {
          if (entry.value) {
            return amenities.contains(entry.key);
          }
          return true;
        });

        return capacityFilter && priceFilter && amenitiesFilter;
      }).toList();
    });
  }

  Widget _buildCapacityFilter(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Capacity (pax)',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        RangeSlider(
          values: _capacityRange,
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.primary.withOpacity(0.2),
          labels: RangeLabels(
            '${_capacityRange.start.round()} pax',
            _capacityRange.end.round() == 10
                ? '10+ pax'
                : '${_capacityRange.end.round()} pax',
          ),
          onChanged: (values) {
            setModalState(() {
              _capacityRange = values;
            });
          },
        ),
      ],
    );
  }

  Widget _buildPriceFilter(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Price Range (per month)',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        RangeSlider(
          values: _priceRange,
          min: 0,
          max: 10000,
          divisions: 100,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.primary.withOpacity(0.2),
          labels: RangeLabels(
            '₱${_priceRange.start.round()}',
            '₱${_priceRange.end.round()}',
          ),
          onChanged: (values) {
            setModalState(() {
              _priceRange = values;
            });
          },
        ),
      ],
    );
  }

  Widget _buildAmenitiesFilter(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Amenities',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: _amenities.values.expand((list) => list).map((amenity) {
            final isSelected = _selectedAmenities[amenity] ?? false;
            return FilterChip(
              label: Text(amenity),
              selected: isSelected,
              onSelected: (selected) {
                setModalState(() {
                  _selectedAmenities[amenity] = selected;
                });
              },
              backgroundColor: Colors.white,
              selectedColor: AppColors.primary.withOpacity(0.15),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRatingStars(double rating, int reviewCount) {
    if (reviewCount == 0) {
      return const Text(
        'No reviews yet',
        style: TextStyle(fontSize: 14, color: Colors.white70),
      );
    }

    List<Widget> stars = [];
    int fullStars = rating.floor();
    bool hasHalfStar = (rating - fullStars) >= 0.5;

    
    for (int i = 0; i < fullStars; i++) {
      stars.add(const Icon(Icons.star, color: Colors.amber, size: 20));
    }

    
    if (hasHalfStar) {
      stars.add(const Icon(Icons.star_half, color: Colors.amber, size: 20));
    }

    
    int emptyStars = 5 - stars.length;
    for (int i = 0; i < emptyStars; i++) {
      stars.add(const Icon(Icons.star_border, color: Colors.amber, size: 20));
    }

    return Row(
      children: [
        ...stars,
        const SizedBox(width: 8),
        Text(
          '${rating.toStringAsFixed(1)} ($reviewCount reviews)',
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
      ],
    );
  }

  Future<bool> _showBookingDialog(
    BuildContext context,
    String roomId,
    String roomName,
    String ownerId,
    String propertyName,
    Map<String, dynamic> roomData,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.data() ?? {};
    final seekerPhoneNumber = userData['phoneNumber'] ?? '';

    int selectedOccupants = 1;
    DateTime? selectedDate;
    final maxCapacity = roomData['capacity'] ?? 1;
    final roomPrice = roomData['price'] ?? 0;

    final bool? bookingSuccess = await showDialog<bool>(
      barrierDismissible: false, 
      context: context,
      builder: (ctx) {
        bool isBooking = false; 
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bool isValidOccupants = selectedOccupants <= maxCapacity;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Booking Details',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    
                    Row(
                      children: [
                        Icon(Icons.bed, size: 25, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            roomName,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    
                    Row(
                      children: [
                        const Icon(
                          Icons.payments,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₱$roomPrice',
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          ' /month',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    
                    Row(
                      children: [
                        Icon(Iconsax.people, size: 20, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Max Capacity: $maxCapacity ${maxCapacity == 1 ? 'person' : 'pax'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    
                    const Text(
                      'Number of Occupants',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isValidOccupants
                              ? Colors.grey[300]!
                              : Colors.red,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: isBooking || selectedOccupants <= 1
                                ? null
                                : () =>
                                      setDialogState(() => selectedOccupants--),
                            icon: const Icon(Icons.remove_circle),
                            color: Colors.blue,
                            disabledColor: Colors.grey,
                          ),
                          Text(
                            '$selectedOccupants ${selectedOccupants == 1 ? 'pax' : 'pax'}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isValidOccupants
                                  ? Colors.black
                                  : Colors.red,
                            ),
                          ),
                          IconButton(
                            onPressed: isBooking
                                ? null
                                : () =>
                                      setDialogState(() => selectedOccupants++),
                            icon: const Icon(Icons.add_circle),
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    ),
                    if (!isValidOccupants) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Exceeds maximum capacity of $maxCapacity',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    
                    const Text(
                      'Move-in Date',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        if (isBooking) return;
                        final DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(
                            const Duration(days: 1),
                          ),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: Colors.blueAccent,
                                  onPrimary: Colors.white,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (pickedDate != null) {
                          setDialogState(() => selectedDate = pickedDate);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey[300]!,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  color: Colors.blue[700],
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  selectedDate == null
                                      ? 'Select a date'
                                      : DateFormat(
                                          'MMM d, yyyy',
                                        ).format(selectedDate!),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: selectedDate == null
                                        ? Colors.grey[600]
                                        : Colors.black87,
                                    fontWeight: selectedDate == null
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.grey,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: isBooking
                          ? null
                          : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        side: BorderSide(color: Colors.grey[400]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed:
                          (isValidOccupants &&
                              selectedDate != null &&
                              !isBooking)
                          ? () async {
                              setDialogState(() {
                                isBooking = true;
                              });
                              final success = await _confirmBooking(
                                context,
                                roomId,
                                roomName,
                                ownerId,
                                propertyName,
                                selectedOccupants,
                                selectedDate!,
                                seekerPhoneNumber,
                              );
                              if (context.mounted) {
                                
                                
                                Navigator.pop(context, success);
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        disabledBackgroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: isBooking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Confirm',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    return bookingSuccess ?? false;
  }

  Future<bool> _confirmBooking(
    BuildContext context,
    String roomId,
    String roomName,
    String ownerId,
    String propertyName,
    int numberOfOccupants,
    DateTime moveInDate,
    String seekerPhoneNumber,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final seekerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final propertyDoc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId) 
          .get();

      final roomDoc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId) 
          .collection('rooms')
          .doc(roomId)
          .get();

      final seekerData = seekerDoc.data() ?? {};
      final propertyData = propertyDoc.data() ?? {};
      final roomData = roomDoc.data() ?? {};

      final seekerName =
          '${seekerData['firstName'] ?? ''} ${seekerData['lastName'] ?? ''}'
              .trim();
      final propertyAddress = propertyData['address'] ?? 'No address specified';
      final roomPrice = roomData['price'] ?? 0;

      final verificationData =
          propertyData['verificationData'] as Map<String, dynamic>?;
      final propertyImageUrl =
          verificationData?['propertyFrontUrl'] as String? ?? '';

      
      final existingBookingQuery = await FirebaseFirestore.instance
          .collection('bookings')
          .where('seekerId', isEqualTo: user.uid)
          .where('propertyId', isEqualTo: widget.propertyId)
          .where('status', whereIn: ['pending', 'awaiting_payment'])
          .limit(1)
          .get();

      final bookingData = {
        'seekerId': user.uid,
        'seekerName': seekerName.isNotEmpty ? seekerName : 'Anonymous Seeker',
        'seekerImageUrl': seekerData['profileImageUrl'],
        'seekerEmail': seekerData['email'] ?? user.email,
        'seekerPhoneNumber': seekerPhoneNumber,
        'seekerDateOfBirth': seekerData['dateOfBirth'],
        'seekerGender': seekerData['gender'] ?? seekerData['sex'],
        'numberOfOccupants': numberOfOccupants,
        'ownerId': ownerId,
        'propertyId': widget.propertyId, 
        'propertyName': propertyName,
        'propertyAddress': propertyAddress,
        'propertyImageUrl': propertyImageUrl,
        'roomId': roomId,
        'roomName': roomName,
        'roomPrice': roomPrice,
        'bookingDate': Timestamp.fromDate(moveInDate),
        'status': 'pending', 
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (existingBookingQuery.docs.isNotEmpty) {
        
        final existingBookingId = existingBookingQuery.docs.first.id;
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(existingBookingId)
            .update(bookingData);
      } else {
        
        await FirebaseFirestore.instance.collection('bookings').add({
          ...bookingData,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        await _updateMonthlyBookingStats(
          widget.propertyId,
          DateFormat('yyyy-MM').format(DateTime.now()),
          'requests',
        );
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send booking request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _updateMonthlyBookingStats(
    String propertyId,
    String month,
    String type,
  ) async {
    final statsRef = FirebaseFirestore.instance
        .collection('properties')
        .doc(propertyId)
        .collection('bookingStats')
        .doc(month);

    await statsRef.set({
      type: FieldValue.increment(1),
      'month': month,
    }, SetOptions(merge: true));
  }

  Future<bool> _hasActiveBookingForRoom(String roomId, String userId) async {
    final bookings = await FirebaseFirestore.instance
        .collection('bookings')
        .where('seekerId', isEqualTo: userId)
        .where('roomId', isEqualTo: roomId)
        .where('status', whereIn: ['pending', 'awaiting_payment'])
        .limit(1)
        .get();

    return bookings.docs.isNotEmpty;
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

  void _showMapDialog(
    BuildContext context,
    GeoPoint location,
    String propertyName,
  ) {
    final LatLng propertyLatLng = LatLng(location.latitude, location.longitude);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Stack(
                children: [
                  GoogleMap(
                    mapType: MapType.hybrid,
                    initialCameraPosition: CameraPosition(
                      target: propertyLatLng,
                      zoom: 16.5,
                      tilt: 30,
                    ),
                    markers: {
                      Marker(
                        markerId: MarkerId(widget.propertyId),
                        position: propertyLatLng,
                        icon:
                            _customMarkerIcon ?? BitmapDescriptor.defaultMarker,
                      ),
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false, 
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        propertyName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.white.withOpacity(0.9),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.close, color: AppColors.textDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .snapshots(),
      builder: (context, propertySnapshot) {
        if (propertySnapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Iconsax.warning_2, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${propertySnapshot.error}'),
                ],
              ),
            ),
          );
        }

        if (!propertySnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final propertyData =
            propertySnapshot.data!.data() as Map<String, dynamic>? ?? {};
        final propertyName = propertyData['name'] ?? 'Property';
        final propertyAddress = propertyData['address'] ?? 'No address';
        final ownerId = propertyData['ownerId'] ?? '';
        final averageRating =
            (propertyData['averageRating'] as num?)?.toDouble() ?? 0.0;
        final ratingCount = propertyData['ratingCount'] as int? ?? 0;

        final verificationData =
            propertyData['verificationData'] as Map<String, dynamic>?;
        final GeoPoint? location = propertyData['location'];
        final propertyImageUrl =
            verificationData?['propertyFrontUrl'] as String?;

        return Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: MediaQuery.of(context).size.height * 0.25,
                    pinned: true,
                    backgroundColor: Colors.transparent,
                    leading: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      if (location != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Iconsax.map_1,
                                color: Colors.white,
                              ),
                            ),
                            tooltip: 'Show on Map',
                            onPressed: () =>
                                _showMapDialog(context, location, propertyName),
                          ),
                        ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (propertyImageUrl != null &&
                              propertyImageUrl.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: propertyImageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[300],
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[300],
                                child: const Icon(
                                  Iconsax.building_3,
                                  size: 60,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          else
                            Container(
                              color: Colors.grey[300],
                              child: const Icon(
                                Iconsax.building_3,
                                size: 60,
                                color: Colors.grey,
                              ),
                            ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.7),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(ownerId)
                                  .get(),
                              builder: (context, ownerSnapshot) {
                                String ownerPhone = 'Loading...';
                                if (ownerSnapshot.hasData &&
                                    ownerSnapshot.data!.exists) {
                                  final ownerData =
                                      ownerSnapshot.data!.data()
                                          as Map<String, dynamic>?;
                                  ownerPhone =
                                      ownerData?['phoneNumber'] ??
                                      'Not available';
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      propertyName,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black,
                                            blurRadius: 4,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildRatingStars(
                                      averageRating,
                                      ratingCount,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            propertyAddress,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.white,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 4,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.phone,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          ownerPhone,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.white,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black,
                                                blurRadius: 4,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Available Rooms',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          InkWell(
                            onTap: _showFilterBottomSheet,
                            borderRadius: BorderRadius.circular(30),
                            child: Ink(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(100),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.filter_list,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Filter',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: propertySnapshot.data!.reference
                        .collection('rooms')
                        .where('verificationStatus', isEqualTo: 'verified')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, roomSnapshot) {
                      if (roomSnapshot.hasError) {
                        return SliverToBoxAdapter(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: Colors.red,
                                ),
                                const SizedBox(height: 16),
                                Text("Error: ${roomSnapshot.error}"),
                              ],
                            ),
                          ),
                        );
                      }

                      if (roomSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const SliverToBoxAdapter(
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      _allRooms = roomSnapshot.data?.docs ?? [];
                      if (_filteredRooms.isEmpty &&
                          _selectedAmenities.isEmpty &&
                          _capacityRange.start == 1 &&
                          _capacityRange.end == 10 &&
                          _priceRange.start == 0 &&
                          _priceRange.end == 10000) {
                        _filteredRooms = _allRooms;
                      }

                      final rooms = _filteredRooms;

                      if (rooms.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.bed_outlined,
                                    size: 80,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  "No rooms available",
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Check back later for new listings",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final roomDoc = rooms[index];
                            final data =
                                roomDoc.data()! as Map<String, dynamic>;
                            final images = List<String>.from(
                              data['images'] ?? [],
                            );
                            final price = data['price']?.toString() ?? '0';
                            final status = data['status'] ?? 'available';
                            final ownerId = data['ownerId'] ?? '';
                            final roomName = data['name'] ?? 'Untitled Room';
                            final capacity =
                                data['capacity']?.toString() ?? '1';
                            final description = data['description'] ?? '';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                              shadowColor: Colors.black.withOpacity(0.1),
                              child: InkWell(
                                onTap: () {
                                  _recordTap(roomDoc.reference);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SeekerRoomDetailsPage(
                                        roomId: roomDoc.id,
                                        data: data,
                                      ),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(16),
                                        topRight: Radius.circular(16),
                                      ),
                                      child: _RoomImageCarousel(
                                        images: images,
                                        status: status,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  roomName,
                                                  style: const TextStyle(
                                                    fontSize: 25,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black87,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: status == 'available'
                                                      ? Colors.green
                                                      : status == 'on_hold'
                                                      ? Colors.orange
                                                      : Colors.red,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  status == 'on_hold'
                                                      ? 'ON HOLD'
                                                      : status.toUpperCase(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Text(
                                                "₱$price",
                                                style: const TextStyle(
                                                  fontFamily: 'Roboto',
                                                  fontSize: 24,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                ' /month',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.people,
                                                size: 20,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                "Capacity: $capacity pax",
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (description.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              description,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[600],
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 16),
                                          if (status == 'occupied')
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Center(
                                                child: Text(
                                                  'Currently Occupied',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else if (status == 'on_hold')
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange[100],
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.orange[300]!,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.pause_circle_outline,
                                                    color: Colors.orange[700],
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Temporarily Unavailable',
                                                    style: TextStyle(
                                                      color: Colors.orange[700],
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            FutureBuilder<bool>(
                                              future: _hasActiveBookingForRoom(
                                                roomDoc.id,
                                                FirebaseAuth
                                                        .instance
                                                        .currentUser
                                                        ?.uid ??
                                                    '',
                                              ),
                                              builder: (context, snapshot) {
                                                if (snapshot.connectionState ==
                                                    ConnectionState.waiting) {
                                                  return const Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  );
                                                }

                                                final hasActiveBooking =
                                                    snapshot.data ?? false;

                                                if (hasActiveBooking) {
                                                  return Container(
                                                    width: double.infinity,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 12,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.orange[50],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      border: Border.all(
                                                        color:
                                                            Colors.orange[200]!,
                                                        width: 2,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(
                                                          Icons.pending_actions,
                                                          color: Colors
                                                              .orange[700],
                                                          size: 20,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Text(
                                                          'Booking Request Sent',
                                                          style: TextStyle(
                                                            color: Colors
                                                                .orange[700],
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }

                                                return SizedBox(
                                                  width: double.infinity,
                                                  child: ElevatedButton.icon(
                                                    onPressed: () async {
                                                      final user = FirebaseAuth
                                                          .instance
                                                          .currentUser;
                                                      if (user == null) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'You must be logged in to make a booking.',
                                                            ),
                                                            backgroundColor:
                                                                Colors.red,
                                                          ),
                                                        );
                                                        return;
                                                      }

                                                      final existingActiveBooking =
                                                          await FirebaseFirestore
                                                              .instance
                                                              .collection(
                                                                'bookings',
                                                              )
                                                              .where(
                                                                'seekerId',
                                                                isEqualTo:
                                                                    user.uid,
                                                              )
                                                              .where(
                                                                'status',
                                                                isEqualTo:
                                                                    'booked',
                                                              )
                                                              .limit(1)
                                                              .get();

                                                      if (existingActiveBooking
                                                          .docs
                                                          .isNotEmpty) {
                                                        if (!context.mounted)
                                                          return;
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'You already have an active booking. You cannot book another room until you vacate your current room.',
                                                            ),
                                                            backgroundColor:
                                                                Colors.orange,
                                                            duration: Duration(
                                                              seconds: 4,
                                                            ),
                                                          ),
                                                        );
                                                        return;
                                                      }

                                                      final bool bookingMade =
                                                          await _showBookingDialog(
                                                            context,
                                                            roomDoc.id,
                                                            roomName,
                                                            ownerId,
                                                            propertyName,
                                                            data,
                                                          );

                                                      
                                                      if (bookingMade &&
                                                          context.mounted) {
                                                        _confettiController
                                                            .play();

                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Booking request sent! The owner will be in touch soon.',
                                                            ),
                                                            backgroundColor:
                                                                Colors.green,
                                                            duration: Duration(
                                                              seconds: 3,
                                                            ),
                                                          ),
                                                        );

                                                        await Future.delayed(
                                                          const Duration(
                                                            seconds: 2,
                                                          ),
                                                        );
                                                        if (context.mounted) {
                                                          Navigator.pop(
                                                            context,
                                                          );
                                                        }
                                                      }
                                                    },
                                                    icon: const Icon(
                                                      Icons.calendar_today,
                                                      color: Colors.white,
                                                      size: 18,
                                                    ),
                                                    label: const Text(
                                                      'Book Now',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.blueAccent,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 12,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }, childCount: rooms.length),
                        ),
                      );
                    },
                  ),
                ],
              ),
              
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  colors: const [
                    Colors.green,
                    Colors.blue,
                    Colors.pink,
                    Colors.orange,
                    Colors.purple,
                  ],
                  emissionFrequency: 0.05,
                  numberOfParticles: 20,
                  gravity: 0.1,
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please log in to start a chat'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (context) => InquiryRoomSelectionDialog(
                    propertyId: widget.propertyId,
                    propertyName: propertyName, 
                  ),
                );

                if (result == null) return;

                final chatQuery = await FirebaseFirestore.instance
                    .collection('chats')
                    .where('propertyId', isEqualTo: widget.propertyId)
                    .where('seekerId', isEqualTo: user.uid)
                    .limit(1)
                    .get();

                String chatId;
                if (chatQuery.docs.isEmpty) {
                  final newChat = await FirebaseFirestore.instance
                      .collection('chats')
                      .add({
                        'ownerId': ownerId,
                        'seekerId': user.uid,
                        'propertyId': widget.propertyId,
                        'propertyName': propertyName,
                        'propertyImageUrl':
                            propertyData['backgroundImageUrl'] ?? '',
                        'lastMessage': '',
                        'lastMessageTime': FieldValue.serverTimestamp(),
                        'unreadByOwner': true,
                        'unreadBySeeker': false,
                      });
                  chatId = newChat.id;
                } else {
                  chatId = chatQuery.docs.first.id;
                }

                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SeekerChatPage(
                      chatId: chatId,
                      ownerId: ownerId,
                      autoSendRoomId: result['roomId'],
                      autoSendRoomData: result['roomData'],
                    ),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Iconsax.message, color: Colors.white),
            label: const Text(
              "Inquire",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.blueAccent,
          ),
        );
      },
    );
  }
}

class _RoomImageCarousel extends StatefulWidget {
  final List<String> images;
  final String status;

  const _RoomImageCarousel({required this.images, required this.status});

  @override
  State<_RoomImageCarousel> createState() => _RoomImageCarouselState();
}

class _RoomImageCarouselState extends State<_RoomImageCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: widget.images.isNotEmpty ? widget.images.length : 1,
            itemBuilder: (context, i) {
              if (widget.images.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.grey[300]!, Colors.grey[200]!],
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.bed, size: 60, color: Colors.grey),
                  ),
                );
              }

              return CachedNetworkImage(
                imageUrl: widget.images[i],
                fit: BoxFit.cover,
                width: double.infinity,
                height: 200,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.blueAccent,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.images.length > 1)
          Positioned(
            bottom: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.images.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == i ? 16 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == i ? Colors.white : Colors.white54,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        
        if (widget.status == 'occupied' || widget.status == 'on_hold')
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.6)),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: widget.status == 'occupied'
                        ? Colors.redAccent
                        : Colors.orange,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.status == 'occupied' ? 'OCCUPIED' : 'ON HOLD',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}