
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/owner_module/bookings/room_booking_requests.dart';

class RoomBookingRequestsList extends StatelessWidget {
  final String propertyId;
  final String propertyName;
  final String ownerId;

  const RoomBookingRequestsList({
    super.key,
    required this.propertyId,
    required this.propertyName,
    required this.ownerId,
  });

  Future<Map<String, int>> _getBookingCountsPerRoom(
    List<QueryDocumentSnapshot> rooms,
  ) async {
    final Map<String, int> counts = {};
    for (final room in rooms) {
      final bookings = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerId', isEqualTo: ownerId)
          .where('roomId', isEqualTo: room.id)
          .where('status', whereIn: ['pending', 'awaiting_payment'])
          .get();
      counts[room.id] = bookings.size;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Booking Requests',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            Text(
              propertyName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: AppColors.blue900,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('properties')
            .doc(propertyId)
            .collection('rooms')
            .where('status', isEqualTo: 'available')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, roomSnapshot) {
          if (roomSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (roomSnapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${roomSnapshot.error}'),
                ],
              ),
            );
          }

          final rooms = roomSnapshot.data?.docs ?? [];

          if (rooms.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.meeting_room, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No rooms available for booking',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All rooms are occupied',
                    style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return FutureBuilder<Map<String, int>>(
            future: _getBookingCountsPerRoom(rooms),
            builder: (context, countSnapshot) {
              if (countSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final bookingCounts = countSnapshot.data ?? {};

              
              final roomsWithBookings = rooms.where((room) {
                return (bookingCounts[room.id] ?? 0) > 0;
              }).toList();

              if (roomsWithBookings.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        'No booking requests',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: roomsWithBookings.length,
                itemBuilder: (context, index) {
                  final roomDoc = roomsWithBookings[index];
                  final roomData = roomDoc.data() as Map<String, dynamic>;
                  final roomId = roomDoc.id;
                  final roomName = roomData['name'] ?? 'Untitled Room';
                  final roomPrice = roomData['price'] ?? 0;
                  final images = List<String>.from(roomData['images'] ?? []);
                  final requestCount = bookingCounts[roomId] ?? 0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RoomBookingRequestsPage(
                              propertyId: propertyId,
                              roomId: roomId,
                              roomName: roomName,
                              propertyName: propertyName,
                              ownerId: ownerId,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: images.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: images.first,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        width: 100,
                                        height: 100,
                                        color: Colors.grey[300],
                                        child: const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                            width: 100,
                                            height: 100,
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.bed),
                                          ),
                                    )
                                  : Container(
                                      width: 100,
                                      height: 100,
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.bed, size: 40),
                                    ),
                            ),
                            const SizedBox(width: 16),
                            
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    roomName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        '₱$roomPrice',
                                        style: const TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: 16,
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '/month',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[100],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.person,
                                          size: 16,
                                          color: Colors.orange[900],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$requestCount ${requestCount == 1 ? 'Request' : 'Requests'}',
                                          style: TextStyle(
                                            color: Colors.orange[900],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
