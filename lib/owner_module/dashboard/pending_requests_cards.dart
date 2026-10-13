


import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rume/components/app_colors.dart';

class PendingRequestsCards extends StatelessWidget {
  final String propertyId;
  final String ownerId;

  const PendingRequestsCards({
    super.key,
    required this.propertyId,
    required this.ownerId,
  });

  Future<Map<String, int>> _getPendingCounts() async {
    try {
      
      final bookingsQuery = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerId', isEqualTo: ownerId)
          .where('propertyId', isEqualTo: propertyId)
          .where('status', whereIn: ['pending', 'awaiting_payment'])
          .count()
          .get();

      
      final propertyDoc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(propertyId)
          .get();
      final propertyPending =
          (propertyDoc.exists && propertyDoc.data()?['status'] == 'pending')
          ? 1
          : 0;

      
      final roomsSnapshot = await FirebaseFirestore.instance
          .collection('properties')
          .doc(propertyId)
          .collection('rooms')
          .where('verificationStatus', whereIn: ['pending', 'reverify'])
          .get();

      return {
        'bookings': bookingsQuery.count ?? 0,
        'property': propertyPending,
        'rooms': roomsSnapshot.size,
      };
    } catch (e) {
      debugPrint('Error getting pending counts: $e');
      return {'bookings': 0, 'property': 0, 'rooms': 0};
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _getPendingCounts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final counts =
            snapshot.data ?? {'bookings': 0, 'property': 0, 'rooms': 0};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pending Requests',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.blue900,
              ),
            ),
            const SizedBox(height: 12),
            
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: IntrinsicHeight(
                
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _buildPendingItem(
                        label: 'Booking Requests',
                        count: counts['bookings']!,
                        color: Colors.blue,
                        icon: Icons.pending_actions,
                      ),
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: 20,
                      endIndent: 20,
                    ),
                    Expanded(
                      child: _buildPendingItem(
                        label: 'Property Verification',
                        count: counts['property']!,
                        color: Colors.green.shade900,
                        icon: Icons.verified_user_outlined,
                      ),
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: 20,
                      endIndent: 20,
                    ),
                    Expanded(
                      child: _buildPendingItem(
                        label: 'Room Verification',
                        count: counts['rooms']!,
                        color: Colors.green,
                        icon: Icons.meeting_room_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  
  Widget _buildPendingItem({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}