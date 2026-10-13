
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:iconsax/iconsax.dart';

class PropertySummaryCard extends StatelessWidget {
  final DocumentSnapshot propertyDoc;
  final String ownerId;

  const PropertySummaryCard({
    super.key,
    required this.propertyDoc,
    required this.ownerId,
  });

  Future<Map<String, int>> _getRoomCounts() async {
    try {
      final roomsSnapshot = await FirebaseFirestore.instance
          .collection('properties')
          .doc(propertyDoc.id)
          .collection('rooms')
          .where('verificationStatus', isEqualTo: 'verified')
          .get();

      int available = 0;
      int occupied = 0;
      int onHold = 0;

      for (var doc in roomsSnapshot.docs) {
        final status = doc.get('status') as String? ?? 'available';
        switch (status) {
          case 'available':
            available++;
            break;
          case 'occupied':
            occupied++;
            break;
          case 'on_hold':
            onHold++;
            break;
        }
      }

      return {
        'total': roomsSnapshot.size,
        'available': available,
        'occupied': occupied,
        'onHold': onHold,
      };
    } catch (e) {
      debugPrint('Error getting room counts: $e');
      return {'total': 0, 'available': 0, 'occupied': 0, 'onHold': 0};
    }
  }

  Future<Map<String, dynamic>> _getMonthlyEarnings() async {
    try {
      final now = DateTime.now();
      final firstDayOfMonth = DateTime(now.year, now.month, 1);
      final lastDayOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      final walletRef = FirebaseFirestore.instance
          .collection('wallets')
          .doc(ownerId);

      final transactionsSnapshot = await walletRef
          .collection('transactions')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(firstDayOfMonth),
          )
          .where(
            'createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(lastDayOfMonth),
          )
          .get();

      double totalEarnings = 0;
      int transactionCount = 0;
      double bookingFees = 0;
      double rentPayments = 0;

      for (var doc in transactionsSnapshot.docs) {
        final data = doc.data();
        final transactionPropertyId = data['propertyId'] as String?;
        if (transactionPropertyId != propertyDoc.id) {
          continue;
        }

        final netAmount = (data['netAmount'] as num?)?.toDouble() ?? 0;
        final paymentType = data['paymentType'] as String? ?? 'rent';

        totalEarnings += netAmount;
        transactionCount++;

        if (paymentType == 'booking') {
          bookingFees += netAmount;
        } else {
          rentPayments += netAmount;
        }
      }

      return {
        'totalEarnings': totalEarnings / 100,
        'transactionCount': transactionCount,
        'bookingFees': bookingFees / 100,
        'rentPayments': rentPayments / 100,
      };
    } catch (e) {
      debugPrint('Error getting monthly earnings: $e');
      return {
        'totalEarnings': 0.0,
        'transactionCount': 0,
        'bookingFees': 0.0,
        'rentPayments': 0.0,
      };
    }
  }

  int _getTotalViews() {
    try {
      final viewedBy =
          propertyDoc.get('viewedBy') as Map<String, dynamic>? ?? {};
      return viewedBy.length;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertyData = propertyDoc.data() as Map<String, dynamic>;
    final propertyName = propertyData['name'] ?? 'Unnamed Property';
    final totalViews = _getTotalViews();
    final currencyFormatter = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const RadialGradient(
            center: Alignment.topLeft,
            radius: 1.2,
            colors: [
              Color.fromARGB(255, 103, 194, 237),
              Color.fromARGB(255, 22, 104, 197),
              Color.fromARGB(255, 11, 63, 142),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              Row(
                children: [
                  const Icon(Iconsax.home, color: Colors.white, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      propertyName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              
              FutureBuilder<Map<String, int>>(
                future: _getRoomCounts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatItem(
                                icon: Iconsax.buildings,
                                label: 'Total Rooms',
                                value: '...',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatItem(
                                icon: Iconsax.eye,
                                label: 'Total Views',
                                value: '$totalViews',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                    );
                  }

                  final counts =
                      snapshot.data ??
                      {'total': 0, 'available': 0, 'occupied': 0, 'onHold': 0};

                  return Column(
                    children: [
                      
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatItem(
                              icon: Iconsax.buildings,
                              label: 'Total Rooms',
                              value: '${counts['total']}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatItem(
                              icon: Iconsax.eye,
                              label: 'Total Views',
                              value: '$totalViews',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(50),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildCombinedRoomStatus(
                                label: 'Available',
                                count: counts['available']!,
                                color: const Color.fromARGB(255, 116, 235, 120),
                                icon: Iconsax.tick_circle,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 50,
                              color: const Color.fromARGB(104, 255, 255, 255),
                            ),
                            Expanded(
                              child: _buildCombinedRoomStatus(
                                label: 'Occupied',
                                count: counts['occupied']!,
                                color: const Color.fromARGB(255, 252, 91, 91),
                                icon: Iconsax.profile_2user,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 50,
                              color: const Color.fromARGB(104, 255, 255, 255),
                            ),
                            Expanded(
                              child: _buildCombinedRoomStatus(
                                label: 'On Hold',
                                count: counts['onHold']!,
                                color: const Color.fromARGB(255, 255, 230, 42),
                                icon: Iconsax.pause_circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),

              
              FutureBuilder<Map<String, dynamic>>(
                future: _getMonthlyEarnings(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.0),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  }

                  final data =
                      snapshot.data ??
                      {
                        'totalEarnings': 0.0,
                        'transactionCount': 0,
                        'bookingFees': 0.0,
                        'rentPayments': 0.0,
                      };

                  return Column(
                    children: [
                      
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(50),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(50),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withAlpha(50),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Icon(
                                    Iconsax.wallet_1,
                                    color: Colors.white,
                                    size: 25,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Monthly Earnings',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        currencyFormatter.format(
                                          data['totalEarnings'],
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Roboto', 
                                          shadows: [
                                            Shadow(
                                              color: Colors.black26,
                                              offset: Offset(0, 2),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Iconsax.receipt_item,
                                            color: Colors.white.withOpacity(
                                              0.6,
                                            ),
                                            size: 14,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${data['transactionCount']} transactions',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.6,
                                              ),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            
                            Container(
                              height: 1,
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(60)
                              ),
                            ),

                            const SizedBox(height: 20),

                            
                            Row(
                              children: [
                                Expanded(
                                  child: _buildEarningsBreakdown(
                                    label: 'Booking Fees',
                                    amount: currencyFormatter.format(
                                      data['bookingFees'],
                                    ),
                                    icon: Iconsax.calendar_tick,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildEarningsBreakdown(
                                    label: 'Rent Payments',
                                    amount: currencyFormatter.format(
                                      data['rentPayments'],
                                    ),
                                    icon: Iconsax.home_2,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedRoomStatus({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildEarningsBreakdown({
    required String label,
    required String amount,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
                                            fontFamily: 'Roboto', 
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
