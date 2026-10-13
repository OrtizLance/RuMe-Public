
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:rume/components/app_colors.dart';
import 'package:iconsax/iconsax.dart';

enum TimeFilter { month, day, hour }

class AnalyticsPage extends StatefulWidget {
  final String propertyId;
  final String propertyName;
  final String ownerId;

  const AnalyticsPage({
    super.key,
    required this.propertyId,
    required this.propertyName,
    required this.ownerId,
  });

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  bool _isLoading = true;
  Map<String, dynamic> _analyticsData = {};
  TimeFilter _earningsFilter = TimeFilter.month;
  TimeFilter _bookingStatsFilter = TimeFilter.month;

  @override
  void initState() {
    super.initState();
    _loadAnalyticsData();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => _isLoading = true);

    try {
      
      final roomsSnapshot = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .where('verificationStatus', isEqualTo: 'verified')
          .get();

      int totalRooms = roomsSnapshot.size;
      int availableRooms = 0;
      int occupiedRooms = 0;
      int onHoldRooms = 0;
      double totalRevenue = 0;

      for (var doc in roomsSnapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'available';

        switch (status) {
          case 'available':
            availableRooms++;
            break;
          case 'occupied':
            occupiedRooms++;
            totalRevenue += (data['price'] ?? 0).toDouble();
            break;
          case 'on_hold':
            onHoldRooms++;
            break;
        }
      }

      
      final onlineBookingsSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerId', isEqualTo: widget.ownerId)
          .where('propertyId', isEqualTo: widget.propertyId)
          .where('status', isEqualTo: 'booked')
          .get();

      int onlineOccupancies = onlineBookingsSnapshot.size;

      
      final manualOccupanciesSnapshot = await FirebaseFirestore.instance
          .collection('manualOccupancies')
          .where('ownerId', isEqualTo: widget.ownerId)
          .where('propertyId', isEqualTo: widget.propertyId)
          .where('status', isEqualTo: 'occupied')
          .get();

      int manualOccupancies = manualOccupanciesSnapshot.size;

      
      final bookingsSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerId', isEqualTo: widget.ownerId)
          .where('propertyId', isEqualTo: widget.propertyId)
          .get();

      int totalBookings = bookingsSnapshot.size;
      int pendingBookings = 0;
      int acceptedBookings = 0;
      int declinedBookings = 0;

      for (var doc in bookingsSnapshot.docs) {
        final status = doc.get('status') as String? ?? '';
        switch (status) {
          case 'pending':
          case 'awaiting_payment':
            pendingBookings++;
            break;
          case 'booked':
            acceptedBookings++;
            break;
          case 'declined':
            declinedBookings++;
            break;
        }
      }

      final now = DateTime.now();

      
      List<Map<String, dynamic>> monthlyBookingStats = [];
      for (int i = 0; i < 6; i++) {
        final targetMonth = DateTime(now.year, now.month - (5 - i), 1);
        final monthKey = DateFormat('yyyy-MM').format(targetMonth);

        final statsDoc = await FirebaseFirestore.instance
            .collection('properties')
            .doc(widget.propertyId)
            .collection('bookingStats')
            .doc(monthKey)
            .get();

        final statsData = statsDoc.data() ?? {};

        monthlyBookingStats.add({
          'month': DateFormat('MMM').format(targetMonth),
          'requests': statsData['requests'] ?? 0,
          'booked': statsData['booked'] ?? 0,
        });
      }

      
      List<Map<String, dynamic>> dailyBookingStats = [];
      for (int i = 6; i >= 0; i--) {
        final targetDay = DateTime(now.year, now.month, now.day - i);
        final nextDay = DateTime(now.year, now.month, now.day - i + 1);

        
        final dayBookingsSnapshot = await FirebaseFirestore.instance
            .collection('bookings')
            .where('ownerId', isEqualTo: widget.ownerId)
            .where('propertyId', isEqualTo: widget.propertyId)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(targetDay),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(nextDay))
            .get();

        int requests = dayBookingsSnapshot.size;
        int booked = 0;

        for (var doc in dayBookingsSnapshot.docs) {
          if (doc.get('status') == 'booked') {
            booked++;
          }
        }

        dailyBookingStats.add({
          'day': DateFormat('EEE').format(targetDay),
          'requests': requests,
          'booked': booked,
        });
      }

      
      List<Map<String, dynamic>> hourlyBookingStats = [];
      final today = DateTime(now.year, now.month, now.day);

      
      final currentHour = now.hour;
      final currentIntervalIndex =
          currentHour ~/ 4; 

      
      for (int i = 5; i >= 0; i--) {
        final targetIntervalIndex = (currentIntervalIndex - i) % 6;
        final startHour = targetIntervalIndex * 4;
        final endHour = startHour + 4;

        
        DateTime startTime;
        DateTime endTime;

        if (currentIntervalIndex - i < 0) {
          
          final previousDay = today.subtract(const Duration(days: 1));
          startTime = previousDay.add(Duration(hours: startHour));
          endTime = previousDay.add(Duration(hours: endHour));
        } else {
          
          startTime = today.add(Duration(hours: startHour));
          endTime = today.add(Duration(hours: endHour));
        }

        final bookingsInInterval = await FirebaseFirestore.instance
            .collection('bookings')
            .where('ownerId', isEqualTo: widget.ownerId)
            .where('propertyId', isEqualTo: widget.propertyId)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startTime),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(endTime))
            .get();

        int requests = 0;
        int booked = 0;

        for (var doc in bookingsInInterval.docs) {
          requests++;
          if (doc.get('status') == 'booked') {
            booked++;
          }
        }

        
        String getHourLabel(int hour) {
          if (hour == 0) return '12am';
          if (hour < 12) return '${hour}am';
          if (hour == 12) return '12pm';
          return '${hour - 12}pm';
        }

        final hourLabel = '${getHourLabel(startHour)}-${getHourLabel(endHour)}';

        hourlyBookingStats.add({
          'hour': hourLabel,
          'requests': requests,
          'booked': booked,
        });
      }

      
      List<Map<String, dynamic>> monthlyEarnings = [];
      for (int i = 0; i < 6; i++) {
        final targetMonth = DateTime(now.year, now.month - (5 - i), 1);
        final nextMonth = DateTime(now.year, now.month - (5 - i) + 1, 1);

        final walletRef = FirebaseFirestore.instance
            .collection('wallets')
            .doc(widget.ownerId);

        final transactionsSnapshot = await walletRef
            .collection('transactions')
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(targetMonth),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(nextMonth))
            .where('propertyId', isEqualTo: widget.propertyId)
            .get();

        double monthTotal = 0;
        for (var doc in transactionsSnapshot.docs) {
          monthTotal += ((doc.data()['netAmount'] as num?) ?? 0) / 100;
        }

        monthlyEarnings.add({
          'month': DateFormat('MMM').format(targetMonth),
          'amount': monthTotal,
        });
      }

      
      List<Map<String, dynamic>> dailyEarnings = [];
      for (int i = 6; i >= 0; i--) {
        final targetDay = DateTime(now.year, now.month, now.day - i);
        final nextDay = DateTime(now.year, now.month, now.day - i + 1);

        final walletRef = FirebaseFirestore.instance
            .collection('wallets')
            .doc(widget.ownerId);

        final transactionsSnapshot = await walletRef
            .collection('transactions')
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(targetDay),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(nextDay))
            .where('propertyId', isEqualTo: widget.propertyId)
            .get();

        double dayTotal = 0;
        for (var doc in transactionsSnapshot.docs) {
          dayTotal += ((doc.data()['netAmount'] as num?) ?? 0) / 100;
        }

        dailyEarnings.add({
          'day': DateFormat('EEE').format(targetDay),
          'amount': dayTotal,
        });
      }

      
      List<Map<String, dynamic>> hourlyEarnings = [];

      
      final currentHourForEarnings = now.hour;
      final currentIntervalIndexForEarnings = currentHourForEarnings ~/ 4;

      
      for (int i = 5; i >= 0; i--) {
        final targetIntervalIndex = (currentIntervalIndexForEarnings - i) % 6;
        final startHour = targetIntervalIndex * 4;
        final endHour = startHour + 4;

        
        DateTime startTime;
        DateTime endTime;

        if (currentIntervalIndexForEarnings - i < 0) {
          
          final previousDay = today.subtract(const Duration(days: 1));
          startTime = previousDay.add(Duration(hours: startHour));
          endTime = previousDay.add(Duration(hours: endHour));
        } else {
          
          startTime = today.add(Duration(hours: startHour));
          endTime = today.add(Duration(hours: endHour));
        }

        final walletRef = FirebaseFirestore.instance
            .collection('wallets')
            .doc(widget.ownerId);

        final transactionsSnapshot = await walletRef
            .collection('transactions')
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startTime),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(endTime))
            .where('propertyId', isEqualTo: widget.propertyId)
            .get();

        double hourTotal = 0;
        for (var doc in transactionsSnapshot.docs) {
          hourTotal += ((doc.data()['netAmount'] as num?) ?? 0) / 100;
        }

        
        String getHourLabel(int hour) {
          if (hour == 0) return '12am';
          if (hour < 12) return '${hour}am';
          if (hour == 12) return '12pm';
          return '${hour - 12}pm';
        }

        final hourLabel = '${getHourLabel(startHour)}-${getHourLabel(endHour)}';

        hourlyEarnings.add({'hour': hourLabel, 'amount': hourTotal});
      }

      
      final feedbackSnapshot = await FirebaseFirestore.instance
          .collection('feedbacks')
          .where('propertyId', isEqualTo: widget.propertyId)
          .where('status', isEqualTo: 'approved')
          .get();

      double averageRating = 0;
      int totalFeedback = feedbackSnapshot.size;
      Map<int, int> ratingDistribution = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};

      if (totalFeedback > 0) {
        double totalRating = 0;
        for (var doc in feedbackSnapshot.docs) {
          final rating = ((doc.data()['rating'] as num?) ?? 0).toDouble();
          totalRating += rating;
          ratingDistribution[rating.round()] =
              (ratingDistribution[rating.round()] ?? 0) + 1;
        }
        averageRating = totalRating / totalFeedback;
      }

      
      final propertyDoc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .get();

      final viewedBy =
          propertyDoc.data()?['viewedBy'] as Map<String, dynamic>? ?? {};
      final totalViews = viewedBy.length;

      if (mounted) {
        setState(() {
          _analyticsData = {
            'totalRooms': totalRooms,
            'availableRooms': availableRooms,
            'occupiedRooms': occupiedRooms,
            'onHoldRooms': onHoldRooms,
            'occupancyRate': totalRooms > 0 ? occupiedRooms / totalRooms : 0.0,
            'totalRevenue': totalRevenue,
            'totalBookings': totalBookings,
            'pendingBookings': pendingBookings,
            'acceptedBookings': acceptedBookings,
            'declinedBookings': declinedBookings,
            'monthlyEarnings': monthlyEarnings,
            'dailyEarnings': dailyEarnings,
            'hourlyEarnings': hourlyEarnings,
            'monthlyBookingStats': monthlyBookingStats,
            'dailyBookingStats': dailyBookingStats,
            'hourlyBookingStats': hourlyBookingStats,
            'averageRating': averageRating,
            'totalFeedback': totalFeedback,
            'ratingDistribution': ratingDistribution,
            'totalViews': totalViews,
            'onlineOccupancies': onlineOccupancies,
            'manualOccupancies': manualOccupancies,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading analytics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showFilterMenu(BuildContext context, bool isEarnings) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 150,
        kToolbarHeight + 100,
        20,
        0,
      ),
      items: [
        PopupMenuItem(
          value: TimeFilter.month,
          child: Row(
            children: [
              Icon(
                isEarnings && _earningsFilter == TimeFilter.month ||
                        !isEarnings && _bookingStatsFilter == TimeFilter.month
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text('Last 6 Months'),
            ],
          ),
        ),
        PopupMenuItem(
          value: TimeFilter.day,
          child: Row(
            children: [
              Icon(
                isEarnings && _earningsFilter == TimeFilter.day ||
                        !isEarnings && _bookingStatsFilter == TimeFilter.day
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text('Last 7 Days'),
            ],
          ),
        ),
        PopupMenuItem(
          value: TimeFilter.hour,
          child: Row(
            children: [
              Icon(
                isEarnings && _earningsFilter == TimeFilter.hour ||
                        !isEarnings && _bookingStatsFilter == TimeFilter.hour
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text('Today (4hr intervals)'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        setState(() {
          if (isEarnings) {
            _earningsFilter = value;
          } else {
            _bookingStatsFilter = value;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Scaffold(
      backgroundColor: Colors.white54,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalyticsData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildKeyMetricsGrid(currencyFormatter),
                    const SizedBox(height: 20),
                    _buildOccupancyRateCard(),
                    const SizedBox(height: 20),
                    _buildOccupancyTypePieChart(),
                    const SizedBox(height: 20),
                    _buildMonthlyEarningsChart(currencyFormatter),
                    const SizedBox(height: 20),
                    _buildBookingStatisticsCard(),
                    const SizedBox(height: 20),
                    _buildRatingDistributionCard(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildKeyMetricsGrid(NumberFormat currencyFormatter) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 7,
      crossAxisSpacing: 4,
      childAspectRatio: 1.6,
      children: [
        _buildMetricCard(
          title: 'Total Verified Rooms',
          value: '${_analyticsData['totalRooms'] ?? 0}',
          icon: Iconsax.building_4,
        ),
        _buildMetricCard(
          title: 'Total Views',
          value: '${_analyticsData['totalViews'] ?? 0}',
          icon: Iconsax.eye,
        ),
        _buildMetricCard(
          title: 'Monthly Revenue',
          value: currencyFormatter.format(_analyticsData['totalRevenue'] ?? 0),
          icon: Iconsax.money_recive,
          valueStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Robutu',
            color: Colors.white,
          ),
        ),
        _buildMetricCard(
          title: 'Total Bookings',
          value: '${_analyticsData['totalBookings'] ?? 0}',
          icon: Iconsax.calendar_tick,
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    TextStyle? valueStyle,
  }) {
    return Card(
      elevation: 4,
      shadowColor: Colors.blueAccent.withOpacity(0.3),
      color: Colors.blueAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                value,
                style:
                    valueStyle ??
                    const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOccupancyRateCard() {
    final rate = (_analyticsData['occupancyRate'] ?? 0.0) as double;
    final occupied = (_analyticsData['occupiedRooms'] ?? 0) as int;
    final total = (_analyticsData['totalRooms'] ?? 0) as int;

    return Card(
      elevation: 4,
      color: Colors.blueAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Occupancy Rate',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: CircularPercentIndicator(
                radius: 80.0,
                lineWidth: 15.0,
                percent: rate,
                center: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${(rate * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '$occupied/$total rooms',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
                progressColor: Colors.white,
                backgroundColor: Colors.white.withOpacity(0.2),
                circularStrokeCap: CircularStrokeCap.round,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildOccupancyLegend(
                  'Available',
                  _analyticsData['availableRooms'] ?? 0,
                  Colors.green,
                ),
                _buildOccupancyLegend(
                  'Occupied',
                  _analyticsData['occupiedRooms'] ?? 0,
                  Colors.orange,
                ),
                _buildOccupancyLegend(
                  'On Hold',
                  _analyticsData['onHoldRooms'] ?? 0,
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOccupancyLegend(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOccupancyTypePieChart() {
    final onlineOccupancies = (_analyticsData['onlineOccupancies'] ?? 0) as int;
    final manualOccupancies = (_analyticsData['manualOccupancies'] ?? 0) as int;
    final totalOccupancies = onlineOccupancies + manualOccupancies;

    if (totalOccupancies == 0) {
      return Card(
        color: Colors.blueAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Iconsax.chart_2, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Occupancy Type',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Iconsax.info_circle,
                      size: 48,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No occupancies yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final onlinePercentage = (onlineOccupancies / totalOccupancies) * 100;
    final manualPercentage = (manualOccupancies / totalOccupancies) * 100;

    return Card(
      elevation: 4,
      color: Colors.blueAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Iconsax.chart_2, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Occupancy Type',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 60,
                  sections: [
                    PieChartSectionData(
                      color: Colors.white,
                      value: onlineOccupancies.toDouble(),
                      title: '${onlinePercentage.toStringAsFixed(0)}%',
                      radius: 50,
                      titleStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                    PieChartSectionData(
                      color: Colors.lightBlue.shade100,
                      value: manualOccupancies.toDouble(),
                      title: '${manualPercentage.toStringAsFixed(0)}%',
                      radius: 50,
                      titleStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPieChartLegend('Online', onlineOccupancies, Colors.white),
                _buildPieChartLegend(
                  'Manual',
                  manualOccupancies,
                  Colors.lightBlue.shade100,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChartLegend(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMonthlyEarningsChart(NumberFormat currencyFormatter) {
    List<Map<String, dynamic>> earningsData;
    String timeLabel = 'Earnings';

    switch (_earningsFilter) {
      case TimeFilter.month:
        earningsData = ((_analyticsData['monthlyEarnings'] ?? []) as List)
            .cast<Map<String, dynamic>>();
        timeLabel = 'Monthly Earnings';
        break;
      case TimeFilter.day:
        earningsData = ((_analyticsData['dailyEarnings'] ?? []) as List)
            .cast<Map<String, dynamic>>();
        timeLabel = 'Daily Earnings';
        break;
      case TimeFilter.hour:
        earningsData = ((_analyticsData['hourlyEarnings'] ?? []) as List)
            .cast<Map<String, dynamic>>();
        timeLabel = 'Hourly Earnings';
        break;
    }

    if (earningsData.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Iconsax.chart_1, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Iconsax.filter, size: 20),
                    onPressed: () => _showFilterMenu(context, true),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Center(child: Text('No earnings data available')),
            ],
          ),
        ),
      );
    }

    String getXAxisLabel(Map<String, dynamic> data) {
      switch (_earningsFilter) {
        case TimeFilter.month:
          return data['month'];
        case TimeFilter.day:
          return data['day'];
        case TimeFilter.hour:
          return data['hour'];
      }
    }

    return Card(
      elevation: 4,
      color: Colors.blueAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Iconsax.chart_1, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      timeLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Iconsax.filter,
                    size: 20,
                    color: Colors.white,
                  ),
                  onPressed: () => _showFilterMenu(context, true),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY:
                      earningsData
                          .map((e) => e['amount'] as double)
                          .reduce((a, b) => a > b ? a : b) *
                      1.2,
                  barGroups: earningsData.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value['amount'] as double,
                          color: Colors.white.withAlpha(200),
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < earningsData.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                getXAxisLabel(earningsData[value.toInt()]),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white70,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingStatisticsCard() {
    List<Map<String, dynamic>> statsData;
    String timeLabel = 'Booking Statistics';

    switch (_bookingStatsFilter) {
      case TimeFilter.month:
        statsData = ((_analyticsData['monthlyBookingStats'] ?? []) as List)
            .cast<Map<String, dynamic>>();
        timeLabel = 'Booking Statistics';
        break;
      case TimeFilter.day:
        statsData = ((_analyticsData['dailyBookingStats'] ?? []) as List)
            .cast<Map<String, dynamic>>();
        timeLabel = 'Daily Booking Statistics';
        break;
      case TimeFilter.hour:
        statsData = ((_analyticsData['hourlyBookingStats'] ?? []) as List)
            .cast<Map<String, dynamic>>();
        timeLabel = 'Hourly Booking Statistics';
        break;
    }

    if (statsData.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Iconsax.activity, color: AppColors.blue900),
                      const SizedBox(width: 8),
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Iconsax.filter, size: 20),
                    onPressed: () => _showFilterMenu(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Center(child: Text('No booking statistics available')),
            ],
          ),
        ),
      );
    }

    String getXAxisLabel(Map<String, dynamic> data) {
      switch (_bookingStatsFilter) {
        case TimeFilter.month:
          return data['month'];
        case TimeFilter.day:
          return data['day'];
        case TimeFilter.hour:
          return data['hour'];
      }
    }

    
    double maxValue = 0;
    for (var data in statsData) {
      final requests = (data['requests'] as int).toDouble();
      final booked = (data['booked'] as int).toDouble();
      if (requests > maxValue) maxValue = requests;
      if (booked > maxValue) maxValue = booked;
    }

    return Card(
      elevation: 4,
      color: Colors.blueAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Iconsax.activity, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      timeLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Iconsax.filter,
                    size: 20,
                    color: Colors.white,
                  ),
                  onPressed: () => _showFilterMenu(context, false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(Colors.orange.shade300, 'Requests'),
                const SizedBox(width: 24),
                _buildLegendItem(Colors.lightGreenAccent, 'Booked'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxValue > 0 ? maxValue * 1.2 : 10,
                  lineBarsData: [
                    LineChartBarData(
                      spots: statsData.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          (entry.value['requests'] as int).toDouble(),
                        );
                      }).toList(),
                      isCurved: true,
                      color: Colors.orange.shade300,
                      barWidth: 4,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.orange.withOpacity(0.2),
                      ),
                    ),
                    LineChartBarData(
                      spots: statsData.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          (entry.value['booked'] as int).toDouble(),
                        );
                      }).toList(),
                      isCurved: true,
                      color: Colors.lightGreenAccent,
                      barWidth: 4,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.green.withOpacity(0.2),
                      ),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= statsData.length) {
                            return const SizedBox.shrink();
                          }
                          if (value != index.toDouble()) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              getXAxisLabel(statsData[index]),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white70,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxValue > 0 ? maxValue / 4 : 2,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.white.withOpacity(0.1),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildRatingDistributionCard() {
    final distribution =
        (_analyticsData['ratingDistribution'] ?? {5: 0, 4: 0, 3: 0, 2: 0, 1: 0})
            as Map<int, int>;
    final averageRating = (_analyticsData['averageRating'] ?? 0.0) as double;
    final totalFeedback = (_analyticsData['totalFeedback'] ?? 0) as int;

    return Card(
      elevation: 4,
      color: Colors.blueAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Iconsax.star_1, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Rating Distribution',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          averageRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                        const Icon(
                          Iconsax.star_1,
                          color: Colors.amber,
                          size: 28,
                        ),
                      ],
                    ),
                    Text(
                      '$totalFeedback reviews',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (totalFeedback > 0)
              ...List.generate(5, (index) {
                final stars = 5 - index;
                final count = distribution[stars] ?? 0;
                final percentage = count / totalFeedback;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        '$stars',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Iconsax.star_1, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: percentage,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          color: Colors.amber,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              })
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No ratings yet',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
