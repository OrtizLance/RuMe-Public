
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rume/utils/booking_helpers.dart';

class RoomBookingRequestsPage extends StatelessWidget {
  final String propertyId;
  final String roomId;
  final String roomName;
  final String propertyName;
  final String ownerId;

  const RoomBookingRequestsPage({
    super.key,
    required this.propertyId,
    required this.roomId,
    required this.roomName,
    required this.propertyName,
    required this.ownerId,
  });

  Future<void> _handleBookingRequest(
    BuildContext context,
    String bookingId,
    String decision,
    Map<String, dynamic> bookingData,
  ) async {
    try {
      if (decision == 'accepted') {
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .update({
              'status': 'awaiting_payment',
              'acceptedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

       
        await BookingHelpers.cancelOtherPendingBookings(
          seekerId: bookingData['seekerId'],
          approvedBookingId: bookingId,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking approved! Waiting for seeker payment.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .update({
              'status': 'declined',
              'declinedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking request declined.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  int _calculateAge(Timestamp? dateOfBirth) {
    if (dateOfBirth == null) return 0;
    return BookingHelpers.calculateAge(dateOfBirth.toDate());
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
              'Booking Requests',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            Text(
              roomName,
              style: const TextStyle(
                color: Colors.white70,
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
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('ownerId', isEqualTo: ownerId)
            .where('roomId', isEqualTo: roomId)
            .where('status', whereIn: ['pending', 'awaiting_payment'])
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No booking requests for this room',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final status = data['status'] ?? 'pending';
              final age = _calculateAge(data['seekerDateOfBirth']);
              final occupants = data['numberOfOccupants'] ?? 1;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundImage: data['seekerImageUrl'] != null
                                ? CachedNetworkImageProvider(
                                    data['seekerImageUrl'],
                                  )
                                : null,
                            child: data['seekerImageUrl'] == null
                                ? const Icon(Icons.person, size: 30)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['seekerName'] ?? 'Seeker',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: BookingHelpers.getStatusColor(
                                          status,
                                        ).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        BookingHelpers.getStatusText(status),
                                        style: TextStyle(
                                          color: BookingHelpers.getStatusColor(
                                            status,
                                          ),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
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
                        ],
                      ),
                      const Divider(height: 24, thickness: 1),
                      
                      _buildInfoRow(
                        Icons.home_outlined,
                        'Property',
                        data['propertyName'] ?? 'N/A',
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.location_on_outlined,
                        'Address',
                        data['propertyAddress'] ?? 'N/A',
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.calendar_month_outlined,
                        'Move-in Date',
                        data['bookingDate'] != null
                            ? DateFormat('MMM d, yyyy').format(
                                (data['bookingDate'] as Timestamp).toDate(),
                              )
                            : 'N/A',
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.payments_outlined,
                        'Monthly Rent',
                        '₱${data['roomPrice'] ?? 0}',
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.email_outlined,
                        'Email',
                        data['seekerEmail'] ?? 'N/A',
                      ),
                    
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.phone_outlined,
                        'Phone',
                        data['seekerPhoneNumber'] ?? 'N/A',
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.people_outline,
                        'Occupants',
                        '$occupants ${occupants > 1 ? 'pax' : 'person'}',
                      ),
                     
                      if (status == 'pending') ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _handleBookingRequest(
                                  context,
                                  doc.id,
                                  'declined',
                                  data,
                                ),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Decline'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _handleBookingRequest(
                                  context,
                                  doc.id,
                                  'accepted',
                                  data,
                                ),
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('Accept'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if (status == 'awaiting_payment') ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Waiting for seeker to complete payment',
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 12), 
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(color: Colors.grey[800]),
                ),
              ],  
            ),
          ),
        ),
      ],
    );
  }
}