import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:rume/components/app_colors.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:rume/components/loading_screen.dart';
import 'package:rume/seeker_module/seeker_dashboard/bookmarked_properties_page.dart';
import 'package:rume/seeker_module/inquiries/s_inquiries.dart';
import 'package:iconsax/iconsax.dart';
import 'package:rume/seeker_module/seeker_dashboard/notifications_page.dart';
import 'package:rume/components/currency.dart';

class SeekerDashboardPage extends StatefulWidget {
  const SeekerDashboardPage({super.key});

  @override
  State<SeekerDashboardPage> createState() => _SeekerDashboardPageState();
}

class _SeekerDashboardPageState extends State<SeekerDashboardPage> {
  final User? _user = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? _userData;
  String _userCity = 'Koronadal City';
  String? _userBarangay;
  bool _isLoading = true;
  String _bookingStatus = 'Searching'; 
  
  bool _isRentPaidThisMonth = false;
  Map<String, dynamic>? _activeBookingData;
  String? _bookedPropertyImageUrl;

  List<dynamic> _cities = [];
  List<dynamic> _barangays = [];
  String? _selectedCity;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    
    final dataFetchFuture = () async {
      await _determinePosition();
      await _fetchUserData();
    }();
    final delayFuture = Future.delayed(const Duration(seconds: 1));

    
    await Future.wait([dataFetchFuture, delayFuture]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchUserData() async {
    if (_user == null) return; 
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .get();
    if (mounted && userDoc.exists) {
      setState(() {
        _userData = userDoc.data();
        String fullAddress = _userData?['address'] ?? '';
        if (fullAddress.isNotEmpty) {
          
          final parts = fullAddress.split(', ');
          if (parts.length > 1) {
            _userCity = parts[1]; 
            if (parts.isNotEmpty) {
              _userBarangay = parts[0];
            }
          }
        }
      });
    }
    await _checkBookingStatus();
    await _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final jsonString = await rootBundle.loadString("assets/ph_address.json");
    final data = json.decode(jsonString);
    if (!mounted) return;
    setState(() {
      _cities = data["cities"] ?? [];
      
      if (_cities.any((c) => c['name'] == _userCity)) {
        _selectedCity = _userCity;
        final cityData = _cities.firstWhere((c) => c['name'] == _userCity);
        _barangays = (cityData['barangays'] as List<dynamic>?) ?? [];
        if (_userBarangay != null && _barangays.contains(_userBarangay)) {
        }
      }
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      
      
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }
  }

  Future<void> _checkBookingStatus() async {
    if (_user == null) return;
    final bookings = await FirebaseFirestore.instance
        .collection('bookings')
        .where('seekerId', isEqualTo: _user.uid)
        .where('status', isEqualTo: 'booked')
        .limit(1)
        .get();

    if (bookings.docs.isNotEmpty) {
      final bookingData = bookings.docs.first.data()
        ..['id'] = bookings.docs.first.id;
      String? imageUrl;

      
      final propertyId = bookingData['propertyId'];
      if (propertyId != null) {
        final propertyDoc = await FirebaseFirestore.instance
            .collection('properties')
            .doc(propertyId)
            .get();
        if (propertyDoc.exists) {
          imageUrl = propertyDoc.data()?['backgroundImageUrl'] as String?;
        }
      }

      
      if (mounted) {
        setState(() {
          _activeBookingData = bookingData;
          _bookingStatus = 'Booked';
          _bookedPropertyImageUrl = imageUrl;
        });
        await _checkCurrentMonthRentStatus();
      }
    }
  }

  Future<void> _checkCurrentMonthRentStatus() async {
    if (_user == null || _activeBookingData == null) return;

    final now = DateTime.now();
    final moveInDate = (_activeBookingData!['bookingDate'] as Timestamp?)
        ?.toDate();

    
    if (moveInDate != null &&
        moveInDate.year == now.year &&
        moveInDate.month == now.month) {
      if (mounted) setState(() => _isRentPaidThisMonth = true);
      return;
    }

    
    final rentPaidSnapshot = await FirebaseFirestore.instance
        .collection("transactions")
        .where("userId", isEqualTo: _user.uid)
        .where("bookingId", isEqualTo: _activeBookingData!['id'])
        .where("status", isEqualTo: "succeeded")
        .where("paymentType", isEqualTo: "rent")
        .where(
          "createdAt",
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime(now.year, now.month, 1),
          ),
        )
        .where(
          "createdAt",
          isLessThan: Timestamp.fromDate(DateTime(now.year, now.month + 1, 1)),
        )
        .limit(1)
        .get();

    if (mounted) {
      setState(() {
        _isRentPaidThisMonth = rentPaidSnapshot.docs.isNotEmpty;
      });
    }
  }

  void _showLocationChangeModal() {
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
                    "Change Location",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCity,
                    hint: const Text("Select City"),
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
                      });
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () {
                      setState(() {
                        _userCity = _selectedCity ?? _userCity;
                        _userBarangay = null;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text(
                      "Apply",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
    if (_isLoading) {
      return const StandardLoadingScreen();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0, 
        automaticallyImplyLeading: false,
        title: _buildUserHeader(),
        toolbarHeight: 60,
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusCard(),
              if (_bookingStatus == 'Booked') ...[
                const SizedBox(height: 10),
                _buildPaymentStatusCard(),
              ],
              const SizedBox(height: 2),
              _buildInquiryCard(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                child: Text(
                  'Properties in $_userCity',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textBody,
                  ),
                ),
              ),
              _buildPropertyList(query: _getPropertiesQuery().where('city', isEqualTo: _userCity)),
              _buildPropertyList(
                title: 'Popular This Week',
                query: _getPropertiesQuery().orderBy(
                  'ratingCount',
                  descending: true,
                ),
              ),
              _buildPropertyList(
                title: 'Recently Added',
                query: _getPropertiesQuery().orderBy(
                  'createdAt',
                  descending: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Query _getPropertiesQuery() {
    return FirebaseFirestore.instance
        .collection('properties')
        .where('status', isEqualTo: 'verified');
  }

  Widget _buildUserHeader() {
    if (_userData == null) {
      return const SizedBox.shrink();
    }

    final imageUrl = _userData!['profileImageUrl'];
    final firstName = _userData!['firstName'] ?? '';
    final lastName = _userData!['lastName'] ?? '';
    String displayName = '$firstName $lastName'.trim();
    if (displayName.isEmpty) {
      displayName = 'Seeker';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primaryColor.withAlpha(25),
              child: imageUrl != null
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: 40,
                        height: 40,
                        placeholder: (context, url) =>
                            const CircularProgressIndicator(strokeWidth: 2),
                        errorWidget: (context, url, error) => const Icon(
                          Iconsax.user,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    )
                  : Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryColor,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textBody,
                  ),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Iconsax.bookmark, color: Colors.black54),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BookmarkedPropertiesPage(),
                ),
              ),
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_user!.uid)
                  .collection('notifications')
                  .where('read', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                final hasUnread =
                    snapshot.hasData && snapshot.data!.docs.isNotEmpty;
                return Stack(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Iconsax.notification,
                        color: Colors.black54,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsPage(),
                        ),
                      ),
                    ),
                    if (hasUnread)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final bool isBooked = _bookingStatus == 'Booked';
    final bool hasImage =
        isBooked &&
        _bookedPropertyImageUrl != null &&
        _bookedPropertyImageUrl!.isNotEmpty;

    return Card(
      elevation: 4,
      shadowColor: Colors.black.withAlpha(25),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          
          if (hasImage)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: _bookedPropertyImageUrl!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    Container(color: Colors.blue),
              ),
            ),

          
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: hasImage
                      ? [
                          AppColors.oceanStart.withOpacity(1),
                          AppColors.oceanEnd.withOpacity(0.5),
                        ]
                      : [Colors.blue, Colors.blueAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),

          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  isBooked ? Iconsax.building_4 : Iconsax.location,
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: TextStyle(
                        color: Colors.white.withAlpha(204),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _bookingStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!isBooked) ...[
                      const SizedBox(height: 4),
                      Text(
                        'In $_userCity',
                        style: TextStyle(
                          color: Colors.white.withAlpha(230),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                if (!isBooked)
                  TextButton.icon(
                    onPressed: _showLocationChangeModal,
                    icon: const Icon(
                      Iconsax.edit,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: const Text(
                      'Change',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withAlpha(51),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatusCard() {
    final leaveStatus = _activeBookingData?['leaveRequestStatus'] as String?;

    
    if (leaveStatus == 'pending') {
      return _buildFinalSettlementProgressCard();
    }

    
    return Card(
      elevation: 4,
      shadowColor: Colors.black.withAlpha(25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: _isRentPaidThisMonth
                ? [Colors.green.shade600, Colors.green.shade800]
                : [Colors.orange.shade700, Colors.red.shade800],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _isRentPaidThisMonth ? Iconsax.receipt_2_1 : Iconsax.wallet_minus,
              color: Colors.white,
              size: 40,
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly Payment',
                  style: TextStyle(
                    color: Colors.white.withAlpha(204),
                    fontSize: 14,
                  ),
                ),
                Text(
                  _isRentPaidThisMonth ? 'Paid This Month' : 'Rent Due',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (!_isRentPaidThisMonth)
              TextButton.icon(
                onPressed: () => context.go('/checkout'),
                icon: const Icon(
                  Iconsax.wallet_check,
                  color: Colors.white,
                  size: 18,
                ),
                label: const Text(
                  'Pay Now',
                  style: TextStyle(color: Colors.white),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha(51),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinalSettlementProgressCard() {
    final outstandingBalance =
        (_activeBookingData?['outstandingBalance'] as int? ?? 0);
    final leavePaymentStatus = _activeBookingData?['leavePaymentStatus'] as String?;
    final checkoutDate = (_activeBookingData?['checkoutDate'] as Timestamp?)
        ?.toDate();
    final totalRentDue =
        (_activeBookingData?['totalRentDueForStay'] as int? ?? 0);
    final totalRentPaid = (_activeBookingData?['totalRentPaid'] as int? ?? 0);
    final progress = totalRentDue > 0
        ? (totalRentPaid / totalRentDue).clamp(0.0, 1.0)
        : 0.0;

    
    if (leavePaymentStatus == 'fully_paid') {
      return Card(
        elevation: 4,
        shadowColor: Colors.green.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.green.shade600, Colors.green.shade800],
            ),
          ),
          child: Column(
            children: [
              Row(
                children: const [
                  Icon(Iconsax.tick_circle, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Text(
                    "Payment Completed",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Your final balance is settled. The property owner has been notified to finalize your checkout.",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      shadowColor: AppColors.primary.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.blue900],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Iconsax.money_send, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                const Text(
                  "Final Settlement Pending",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "You have a pending leave request. Settle your balance to complete the process.",
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const Divider(height: 24, color: Colors.white24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Outstanding Balance',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  currencyFormatter.format(outstandingBalance / 100),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
            if (checkoutDate != null) ...[
              const SizedBox(height: 8),
              Text(
                "Settle your balance for your checkout on ${DateFormat('MMM d, yyyy').format(checkoutDate)}.",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Payment Progress',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(
                0.3,
              ), 
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.successGreen,
              ),
              minHeight: 25,
              borderRadius: BorderRadius.circular(15),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paid: ${currencyFormatter.format(totalRentPaid / 100)}',
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Total Due: ${currencyFormatter.format(totalRentDue / 100)}',
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/checkout'),
                icon: const Icon(Iconsax.wallet_check),
                label: const Text(
                  'Pay Final Balance',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInquiryCard() {
    return StreamBuilder<QuerySnapshot>(
      
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('seekerId', isEqualTo: _user!.uid)
          .orderBy('lastMessageTime', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, latestChatSnapshot) {
        String? propertyImageUrl;
        if (latestChatSnapshot.hasData &&
            latestChatSnapshot.data!.docs.isNotEmpty) {
          final lastChatData =
              latestChatSnapshot.data!.docs.first.data()
                  as Map<String, dynamic>;
          propertyImageUrl = lastChatData['propertyImageUrl'] as String?;
        }

        return StreamBuilder<QuerySnapshot>(
          
          stream: FirebaseFirestore.instance
              .collection('chats')
              .where('seekerId', isEqualTo: _user.uid)
              .where('unreadBySeeker', isEqualTo: true)
              .snapshots(),
          builder: (context, unreadSnapshot) {
            final hasChats =
                latestChatSnapshot.hasData &&
                latestChatSnapshot.data!.docs.isNotEmpty;
            final unreadCount = unreadSnapshot.data?.docs.length ?? 0;

            return Card(
              elevation: 4,
              shadowColor: Colors.black.withAlpha(25),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  
                  Positioned.fill(
                    child: hasChats
                        ? (propertyImageUrl != null &&
                                  propertyImageUrl.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: propertyImageUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Container(
                                        color: Colors.blueGrey.shade800,
                                      ),
                                )
                              : Container(
                                  color: Colors.blue,
                                ) 
                        : Container(color: Colors.blue), 
                  ),
                  
                  if (hasChats)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.oceanStart.withOpacity(1),
                              AppColors.oceanEnd.withOpacity(0.8),
                              AppColors.oceanEnd.withOpacity(0.7),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                            begin: Alignment.topLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),

                  
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Icon(
                          Iconsax.message_question,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'My Inquiries',
                              style: TextStyle(
                                color: Colors.white.withAlpha(204),
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              unreadCount > 0
                                  ? '$unreadCount Unread Message${unreadCount > 1 ? 's' : ''}'
                                  : 'No Unread Messages',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SeekerInquiriesPage(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Iconsax.message,
                                color: Colors.white,
                                size: 18,
                              ),
                              label: const Text(
                                'View',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white.withAlpha(51),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),

                            if (unreadCount > 0)
                              Positioned(
                                top: 2,
                                right: 5,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPropertyList({String? title, required Query query}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textBody,
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 240,
          child: StreamBuilder<QuerySnapshot>(
            stream: query.limit(10).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No properties found.'));
              }

              final properties = snapshot.data!.docs;

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: properties.length,
                itemBuilder: (context, index) {
                  if (properties.isEmpty) {
                    return const Center(
                      child: Text(
                        'No properties found within the selected radius.',
                      ),
                    );
                  }
                  final property = properties[index];
                  return _buildPropertyCard(property);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRatingStars(double rating, int reviewCount) {
    List<Widget> stars = [];
    int fullStars = rating.floor();
    bool hasHalfStar = (rating - fullStars) >= 0.5;

    
    for (int i = 0; i < fullStars; i++) {
      stars.add(const Icon(Icons.star, color: Colors.amber, size: 16));
    }

    
    if (hasHalfStar) {
      stars.add(const Icon(Icons.star_half, color: Colors.amber, size: 16));
    }

    
    int emptyStars = 5 - stars.length;
    for (int i = 0; i < emptyStars; i++) {
      stars.add(const Icon(Icons.star_border, color: Colors.amber, size: 16));
    }

    return Row(
      children: [
        ...stars,
        const SizedBox(width: 4),
        Text(
          '${rating.toStringAsFixed(1)} ($reviewCount)',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildPropertyCard(DocumentSnapshot property) {
    final data = property.data() as Map<String, dynamic>;
    final imageUrl = data['backgroundImageUrl'] ?? '';
    final name = data['name'] ?? 'Unnamed Property';
    final fullAddress = data['address'] as String? ?? 'N/A';
    if (fullAddress.isNotEmpty) {
      final parts = fullAddress.split(', ');
      if (parts.length > 1) {

      }
    }
    final averageRating = (data['averageRating'] as num?)?.toDouble() ?? 0.0;
    final ratingCount = data['ratingCount'] as int? ?? 0;
    final viewedBy = data['viewedBy'] as Map<String, dynamic>? ?? {};
    final totalViews = viewedBy.length;


    return GestureDetector(
      onTap: () => context.push('/property-rooms/${property.id}'),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Colors.grey[200]),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Iconsax.gallery_slash),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (ratingCount > 0)
                  _buildRatingStars(averageRating, ratingCount)
                else
                  Text(
                    'No reviews yet',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                Row(
                  children: [
                    Icon(
                      Iconsax.eye,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$totalViews',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
