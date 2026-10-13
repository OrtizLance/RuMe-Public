
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iconsax/iconsax.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

class AnalyticsPreviewCard extends StatelessWidget {
  final String propertyId;
  final String ownerId;
  final VoidCallback onViewFullAnalytics;

  const AnalyticsPreviewCard({
    super.key,
    required this.propertyId,
    required this.ownerId,
    required this.onViewFullAnalytics,
  });

  Future<Map<String, dynamic>> _getAnalyticsData() async {
    try {
      
      final roomsSnapshot = await FirebaseFirestore.instance
          .collection('properties')
          .doc(propertyId)
          .collection('rooms')
          .where('verificationStatus', isEqualTo: 'verified')
          .get();

      int totalRooms = roomsSnapshot.size;
      int occupiedRooms = 0;

      for (var doc in roomsSnapshot.docs) {
        final status = doc.get('status') as String? ?? 'available';
        if (status == 'occupied') {
          occupiedRooms++;
        }
      }

      double occupancyRate = totalRooms > 0 ? occupiedRooms / totalRooms : 0.0;

      
      final topRatedRooms = await FirebaseFirestore.instance
          .collection('properties')
          .doc(propertyId)
          .collection('rooms')
          .where('verificationStatus', isEqualTo: 'verified')
          .where('ratingCount', isGreaterThan: 0)
          .orderBy('ratingCount', descending: true)
          .orderBy('averageRating', descending: true)
          .limit(3)
          .get();

      List<Map<String, dynamic>> topRooms = [];
      for (var doc in topRatedRooms.docs) {
        final data = doc.data();
        topRooms.add({
          'name': data['name'] ?? 'Room',
          'rating': (data['averageRating'] ?? 0.0).toDouble(),
          'ratingCount': data['ratingCount'] ?? 0,
        });
      }

      
      topRooms.sort((a, b) {
        final ratingCompare = (b['rating'] as double).compareTo(
          a['rating'] as double,
        );
        if (ratingCompare != 0) return ratingCompare;
        return (b['ratingCount'] as int).compareTo(a['ratingCount'] as int);
      });

      
      final feedbackSnapshot = await FirebaseFirestore.instance
          .collection('feedbacks')
          .where('propertyId', isEqualTo: propertyId)
          .where('status', isEqualTo: 'approved')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .get();

      List<Map<String, dynamic>> latestFeedback = [];
      for (var doc in feedbackSnapshot.docs) {
        final data = doc.data();

        
        String seekerName = 'Unknown';
        try {
          final seekerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(data['seekerId'])
              .get();
          if (seekerDoc.exists) {
            final seekerData = seekerDoc.data()!;
            seekerName =
                '${seekerData['firstName'] ?? ''} ${seekerData['lastName'] ?? ''}'
                    .trim();
            if (seekerName.isEmpty) seekerName = 'Anonymous';
          }
        } catch (e) {
          debugPrint('Error fetching seeker name: $e');
        }

        latestFeedback.add({
          'roomName': data['roomName'] ?? 'Room',
          'seekerName': seekerName,
          'rating': (data['rating'] ?? 0.0).toDouble(),
          'description': data['description'] ?? '',
          'createdAt': data['createdAt'] as Timestamp?,
        });
      }

      return {
        'occupancyRate': occupancyRate,
        'occupiedRooms': occupiedRooms,
        'totalRooms': totalRooms,
        'topRatedRooms': topRooms,
        'latestFeedback': latestFeedback,
      };
    } catch (e) {
      debugPrint('Error getting analytics data: $e');
      return {
        'occupancyRate': 0.0,
        'occupiedRooms': 0,
        'totalRooms': 0,
        'topRatedRooms': [],
        'latestFeedback': [],
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.fromARGB(255, 103, 194, 237),
              Color.fromARGB(255, 22, 104, 197),
              Color.fromARGB(255, 11, 63, 142),
            ],
            stops: const [0.0, 0.2, 0.7],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                    child: const Icon(
                      Iconsax.diagram,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Analytics Overview',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              
              FutureBuilder<Map<String, dynamic>>(
                future: _getAnalyticsData(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
                    );
                  }

                  final data =
                      snapshot.data ??
                      {
                        'occupancyRate': 0.0,
                        'occupiedRooms': 0,
                        'totalRooms': 0,
                        'topRatedRooms': [],
                        'latestFeedback': [],
                      };

                  return Column(
                    children: [
                      _buildOccupancySection(
                        data['occupancyRate'] as double,
                        data['occupiedRooms'] as int,
                        data['totalRooms'] as int,
                      ),

                      const SizedBox(height: 20),
                      Divider(height: 1, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 20),

                      _buildTopRatedRoomsSection(
                        data['topRatedRooms'] as List<Map<String, dynamic>>,
                      ),

                      const SizedBox(height: 20),
                      Divider(height: 1, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 20),

                      _buildLatestFeedbackSection(
                        data['latestFeedback'] as List<Map<String, dynamic>>,
                      ),

                      const SizedBox(height: 20),

                      
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onViewFullAnalytics,
                          icon: const Icon(
                            Iconsax.diagram,
                            color: Color(0xFF1E3A8A),
                          ),  
                          label: const Text(
                            'View Full Analytics',
                            style: TextStyle(
                              color: Color(0xFF1E3A8A),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOccupancySection(double rate, int occupied, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Occupancy Rate',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: CircularPercentIndicator(
            radius: 80.0,
            lineWidth: 14.0,
            percent: rate,
            center: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(rate * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$occupied/$total',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            progressColor: Colors.white,
            backgroundColor: Colors.white.withOpacity(0.2),
            circularStrokeCap: CircularStrokeCap.round,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$occupied rooms occupied out of $total total',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopRatedRoomsSection(List<Map<String, dynamic>> rooms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top Rated Rooms',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        if (rooms.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                'No rated rooms yet',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ),
          )
        else
          ...rooms.map((room) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.star,
                      color: Colors.amber,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room['name'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${room['ratingCount']} reviews',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (room['rating'] as double).toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.star, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildLatestFeedbackSection(List<Map<String, dynamic>> feedback) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Latest Feedback',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        if (feedback.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                'No feedback yet',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ),
          )
        else
          ...feedback.map((fb) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fb['roomName'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'by ${fb['seekerName']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.8),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < (fb['rating'] as double).floor()
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 16,
                          );
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fb['description'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }
}