
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:rume/owner_module/room_listings/room_form_page.dart';
import 'package:cached_network_image/cached_network_image.dart';

class RoomDetailsPage extends StatefulWidget {
  final String propertyId;
  final String roomId;
  final Map<String, dynamic> data;

  const RoomDetailsPage({
    super.key,
    required this.propertyId,
    required this.roomId,
    required this.data,
  });

  @override
  State<RoomDetailsPage> createState() => _RoomDetailsPageState();
}

class _RoomDetailsPageState extends State<RoomDetailsPage> {
  late String _status;
  late String _verificationStatus;
  late Map<String, dynamic> _roomData;

  @override
  void initState() {
    super.initState();
    _roomData = widget.data;
    _status = _roomData['status'] ?? 'available';
    _verificationStatus = _roomData['verificationStatus'] ?? 'pending';
  }

  Future<void> _refreshRoomData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .doc(widget.roomId)
          .get();

      if (doc.exists && mounted) {
        setState(() {
          _roomData = doc.data()!;
          _status = _roomData['status'] ?? 'available';
          _verificationStatus = _roomData['verificationStatus'] ?? 'pending';
        });
      }
    } catch (e) {
      debugPrint('Error refreshing room data: $e');
    }
  }

  Future<void> _deleteRoom(BuildContext context) async {
    final images = List<String>.from(_roomData['images'] ?? []);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Room'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this room? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      
      for (final url in images) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (e) {
          debugPrint('Failed to delete image: $e');
        }
      }

      
      await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .doc(widget.roomId)
          .delete();

      if (context.mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Room deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete room: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateRoomStatus(String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .doc(widget.roomId)
          .update({'status': newStatus});

      if (mounted) {
        setState(() => _status = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Room status updated to ${_getStatusDisplayName(newStatus)}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getStatusDisplayName(String status) {
    switch (status) {
      case 'available':
        return 'Available';
      case 'on_hold':
        return 'On Hold';
      case 'occupied':
        return 'Occupied';
      default:
        return status;
    }
  }

  Future<void> _toggleOnHoldStatus() async {
    if (_status == 'on_hold') {
      await _updateRoomStatus('available');
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.pause_circle, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Put Room On Hold'),
            ],
          ),
          content: const Text(
            'This will temporarily make the room unavailable for bookings. You can make it available again anytime.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _updateRoomStatus('on_hold');
      }
    }
  }

  Future<void> _manualOccupancy() async {
    
    final dialogData = await showDialog<_ManualOccupancyData>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ManualOccupancyDialog(),
    );

    if (dialogData != null && mounted) {
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          throw Exception('User not logged in');
        }

        
        final propertyDoc = await FirebaseFirestore.instance
            .collection('properties')
            .doc(widget.propertyId)
            .get();

        if (!propertyDoc.exists) {
          throw Exception('Property not found');
        }

        final propertyData = propertyDoc.data() ?? {};
        final propertyName = propertyData['name'] ?? 'Unknown Property';

        debugPrint('Creating manual occupancy...');

        
        await FirebaseFirestore.instance.collection('manualOccupancies').add({
          'propertyId': widget.propertyId,
          'propertyName': propertyName,
          'roomId': widget.roomId,
          'roomName': _roomData['name'] ?? 'Unknown Room',
          'roomPrice': _roomData['price'] ?? 0,
          'roomImages': _roomData['images'] ?? [],
          'ownerId': currentUser.uid,
          'numberOfOccupants': dialogData.numberOfOccupants,
          'occupantNames': dialogData.occupantNames,
          'moveInDate': Timestamp.fromDate(dialogData.moveInDate),
          'contactNumber': dialogData.contactNumber,
          'status': 'occupied',
          'type': 'manual',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        debugPrint('✅ Manual occupancy created successfully');

        
        await FirebaseFirestore.instance
            .collection('properties')
            .doc(widget.propertyId)
            .collection('rooms')
            .doc(widget.roomId)
            .update({
              'status': 'occupied',
              'updatedAt': FieldValue.serverTimestamp(),
            });

        debugPrint('✅ Room status updated to occupied');

        
        await _refreshRoomData();

        
        if (mounted) {
          Navigator.pop(context); 

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Manual occupancy recorded successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e, stackTrace) {
        debugPrint('❌ Error recording manual occupancy: $e');
        debugPrint('Stack trace: $stackTrace');

        
        if (mounted) {
          Navigator.pop(context); 

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to record occupancy: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _editRoom() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomFormPage(
          propertyId: widget.propertyId,
          roomId: widget.roomId,
          isReverifying: _verificationStatus == 'verified',
        ),
      ),
    );

    if (result == true) {
      await _refreshRoomData();
    }
  }

  void _showAllAmenities(BuildContext context, List<String> amenities) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'All Amenities',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.5,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: amenities.length,
                  itemBuilder: (context, index) {
                    final amenity = amenities[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        border: Border.all(color: Colors.blue[200]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          amenity.toString(),
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = List<String>.from(_roomData['images'] ?? []);
    final amenities = List<String>.from(_roomData['amenities'] ?? []);
    final price = _roomData['price']?.toString() ?? '0';
    final capacity = _roomData['capacity']?.toString() ?? '1';
    final name = _roomData['name'] ?? 'Unnamed Room';
    final description = _roomData['description'] ?? '';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            backgroundColor: Colors.blueAccent,
            flexibleSpace: FlexibleSpaceBar(
              title: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              background: images.isNotEmpty
                  ? _ImageCarousel(images: images)
                  : Container(
                      color: Colors.grey[300],
                      child: const Icon(
                        Icons.bed,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white, size: 30),
                onPressed: _editRoom,
                tooltip: 'Edit Room',
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 30),
                onPressed: () => _deleteRoom(context),
                tooltip: 'Delete Room',
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Monthly Rent',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₱$price',
                                  style: const TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 28,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _status == 'available'
                                    ? Colors.green
                                    : _status == 'on_hold'
                                    ? Colors.orange
                                    : Colors.red,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (_status == 'available'
                                                ? Colors.green
                                                : _status == 'on_hold'
                                                ? Colors.orange
                                                : Colors.red)
                                            .withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                _getStatusDisplayName(_status).toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(
                              Icons.people,
                              size: 18,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Max capacity: $capacity ${capacity == '1' ? 'person' : 'persons'}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (description.isNotEmpty) ...[
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Description',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            description,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Amenities',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (amenities.isNotEmpty) ...[
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  childAspectRatio: 2.5,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: amenities.length > 9
                                ? 9
                                : amenities.length,
                            itemBuilder: (context, index) {
                              final amenity = amenities[index];
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  border: Border.all(color: Colors.blue[200]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    amenity.toString(),
                                    style: TextStyle(
                                      color: Colors.blue[700],
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            },
                          ),
                          if (amenities.length > 6) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: () =>
                                    _showAllAmenities(context, amenities),
                                child: const Text('View All'),
                              ),
                            ),
                          ],
                        ] else
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'No amenities listed',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_status != 'occupied')
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'Room Management',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _toggleOnHoldStatus,
                              icon: Icon(
                                _status == 'on_hold'
                                    ? Icons.play_circle
                                    : Icons.pause_circle,
                                color: Colors.white,
                              ),
                              label: Text(
                                _status == 'on_hold'
                                    ? 'Make Available'
                                    : 'Put On Hold',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _status == 'on_hold'
                                    ? Colors.green
                                    : Colors.orange,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _manualOccupancy,
                              icon: const Icon(
                                Icons.how_to_reg,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Manual Occupancy',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageCarousel extends StatefulWidget {
  final List<String> images;

  const _ImageCarousel({required this.images});

  @override
  State<_ImageCarousel> createState() => __ImageCarouselState();
}

class __ImageCarouselState extends State<_ImageCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.bed, size: 80, color: Colors.white),
        ),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          onPageChanged: (index) => setState(() => _currentPage = index),
          itemCount: widget.images.length,
          itemBuilder: (context, index) {
            return CachedNetworkImage(
              imageUrl: widget.images[index],
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (context, url) => Container(
                color: Colors.grey[300],
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.error, size: 50, color: Colors.white),
              ),
            );
          },
        ),
        if (widget.images.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.images.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 12 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Colors.white
                        : Colors.white54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}


class _ManualOccupancyData {
  final int numberOfOccupants;
  final List<String> occupantNames;
  final DateTime moveInDate;
  final String contactNumber;

  _ManualOccupancyData({
    required this.numberOfOccupants,
    required this.occupantNames,
    required this.moveInDate,
    required this.contactNumber,
  });
}


class _ManualOccupancyDialog extends StatefulWidget {
  @override
  State<_ManualOccupancyDialog> createState() => _ManualOccupancyDialogState();
}

class _ManualOccupancyDialogState extends State<_ManualOccupancyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameControllers = <TextEditingController>[];
  final _contactController = TextEditingController();
  DateTime _moveInDate = DateTime.now();
  int _numberOfOccupants = 1;

  @override
  void initState() {
    super.initState();
    _nameControllers.add(TextEditingController());
  }

  @override
  void dispose() {
    for (var controller in _nameControllers) {
      controller.dispose();
    }
    _contactController.dispose();
    super.dispose();
  }

  void _updateOccupantCount(int newCount) {
    setState(() {
      _numberOfOccupants = newCount;
      while (_nameControllers.length < _numberOfOccupants) {
        _nameControllers.add(TextEditingController());
      }
      while (_nameControllers.length > _numberOfOccupants) {
        _nameControllers.removeLast().dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.person_add, color: Colors.blue, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text('Manual Occupancy', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Number of Occupants',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _numberOfOccupants,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                items: List.generate(10, (i) => i + 1).map((n) {
                  return DropdownMenuItem(
                    value: n,
                    child: Text('$n ${n == 1 ? 'person' : 'persons'}'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    _updateOccupantCount(value);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Occupant Names',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...List.generate(_numberOfOccupants, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    controller: _nameControllers[index],
                    decoration: InputDecoration(
                      labelText: 'Name ${index + 1}',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Required' : null,
                  ),
                );
              }),
              const SizedBox(height: 16),
              const Text(
                'Move-in Date',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _moveInDate,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _moveInDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.grey[50],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        '${_moveInDate.day}/${_moveInDate.month}/${_moveInDate.year}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Contact Number',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _contactController,
                decoration: InputDecoration(
                  labelText: 'Contact Number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: const Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final data = _ManualOccupancyData(
                numberOfOccupants: _numberOfOccupants,
                occupantNames: _nameControllers
                    .map((c) => c.text.trim())
                    .toList(),
                moveInDate: _moveInDate,
                contactNumber: _contactController.text.trim(),
              );
              Navigator.pop(context, data);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Confirm', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}