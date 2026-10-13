
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:rume/owner_module/bookings/room_occupants.dart';
import 'package:rume/owner_module/bookings/manual_occupants.dart';

class OccupiedRoomsListPage extends StatefulWidget {
  final String propertyId;
  final String propertyName;
  final String ownerId;

  const OccupiedRoomsListPage({
    super.key,
    required this.propertyId,
    required this.propertyName,
    required this.ownerId,
  });

  @override
  State<OccupiedRoomsListPage> createState() => _OccupiedRoomsListPageState();
}

class _OccupiedRoomsListPageState extends State<OccupiedRoomsListPage> {
  String _filterType = 'all'; 

  int _calculateAge(Timestamp? dateOfBirth) {
    if (dateOfBirth == null) return 0;
    final dob = dateOfBirth.toDate();
    final today = DateTime.now();
    int age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age;
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Filter Occupants'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('All Occupants'),
              value: 'all',
              groupValue: _filterType,
              onChanged: (value) {
                setState(() => _filterType = value!);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<String>(
              title: const Text('Online Bookings'),
              value: 'online',
              groupValue: _filterType,
              onChanged: (value) {
                setState(() => _filterType = value!);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<String>(
              title: const Text('Manual Occupancy'),
              value: 'manual',
              groupValue: _filterType,
              onChanged: (value) {
                setState(() => _filterType = value!);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Occupied Rooms',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontSize: 18,
              ),
            ),
            Text(
              widget.propertyName,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Iconsax.filter, color: Colors.white),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _getCombinedOccupancyStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Iconsax.house, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No occupied rooms in this property',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }

          final occupancies = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: occupancies.length,
            itemBuilder: (context, index) {
              final occupancy = occupancies[index];
              final isManual = occupancy['type'] == 'manual';

              if (isManual) {
                return _buildManualOccupancyCard(occupancy);
              } else {
                return _buildOnlineBookingCard(occupancy);
              }
            },
          );
        },
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _getCombinedOccupancyStream() {
    
    final onlineStream = FirebaseFirestore.instance
        .collection('bookings')
        .where('ownerId', isEqualTo: widget.ownerId)
        .where('propertyId', isEqualTo: widget.propertyId)
        .where('status', isEqualTo: 'booked')
        .orderBy('paidAt', descending: true)
        .snapshots();

    
    final manualStream = FirebaseFirestore.instance
        .collection('manualOccupancies')
        .where('ownerId', isEqualTo: widget.ownerId)
        .where('propertyId', isEqualTo: widget.propertyId)
        .where('status', isEqualTo: 'occupied')
        .orderBy('createdAt', descending: true)
        .snapshots();

    
    return onlineStream.asyncMap((onlineSnapshot) async {
      final manualSnapshot = await manualStream.first;

      List<Map<String, dynamic>> combined = [];

      
      if (_filterType == 'all' || _filterType == 'online') {
        for (var doc in onlineSnapshot.docs) {
          final data = doc.data();
          combined.add({...data, 'id': doc.id, 'type': 'online'});
        }
      }

      
      if (_filterType == 'all' || _filterType == 'manual') {
        for (var doc in manualSnapshot.docs) {
          final data = doc.data();
          combined.add({...data, 'id': doc.id, 'type': 'manual'});
        }
      }

      
      combined.sort((a, b) {
        final aDate = a['paidAt'] ?? a['createdAt'];
        final bDate = b['paidAt'] ?? b['createdAt'];
        if (aDate == null || bDate == null) return 0;
        return (bDate as Timestamp).compareTo(aDate as Timestamp);
      });

      return combined;
    });
  }

  Widget _buildOnlineBookingCard(Map<String, dynamic> data) {
    final age = _calculateAge(data['seekerDateOfBirth']);
    final hasLeaveRequest = data['leaveRequestStatus'] == 'pending';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      
      color: hasLeaveRequest ? Colors.red[50] : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          
          border: hasLeaveRequest
              ? Border.all(color: Colors.red[300]!, width: 2)
              : null,
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RoomOccupantDetailsPage(
                  bookingId: data['id'],
                  propertyId: widget.propertyId,
                  roomId: data['roomId'],
                  bookingData: data,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        data['roomName'] ?? 'Room',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'ONLINE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Iconsax.wallet_money,
                      size: 18,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '₱${data['roomPrice'] ?? 0}/month',
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),

                
                if (hasLeaveRequest) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Iconsax.info_circle,
                          size: 18,
                          color: Colors.red[800],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Leave request pending',
                            style: TextStyle(
                              color: Colors.red[900],
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Icon(
                          Iconsax.arrow_right_3,
                          size: 16,
                          color: Colors.red[800],
                        ),
                      ],
                    ),
                  ),
                ],

                const Divider(height: 24, thickness: 1),
                const Text(
                  'Current Occupant',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: data['seekerImageUrl'] != null
                          ? CachedNetworkImageProvider(data['seekerImageUrl'])
                          : null,
                      child: data['seekerImageUrl'] == null
                          ? const Icon(Iconsax.user, size: 24)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['seekerName'] ?? 'Seeker',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${age > 0 ? '$age years old' : 'Age N/A'} • ${data['seekerGender'] ?? 'N/A'}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Iconsax.arrow_right_3,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManualOccupancyCard(Map<String, dynamic> data) {
    final numberOfOccupants = data['numberOfOccupants'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ManualOccupantsPage(
                occupancyId: data['id'],
                propertyId: widget.propertyId,
                roomId: data['roomId'],
                occupancyData: data,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      data['roomName'] ?? 'Room',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'MANUAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Iconsax.wallet_money,
                    size: 18,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '₱${data['roomPrice'] ?? 0}/month',
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 1),
              Row(
                children: [
                  const Icon(Iconsax.people, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    '$numberOfOccupants ${numberOfOccupants == 1 ? 'Occupant' : 'Occupants'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Iconsax.arrow_right_3,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}