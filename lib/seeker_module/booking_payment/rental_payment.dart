import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:rume/components/app_colors.dart';
import 'package:iconsax/iconsax.dart';
import 'package:rume/components/currency.dart';
import 'package:rume/components/loading_screen.dart';
import 'package:rume/seeker_module/booking_payment/final_payment_page.dart';
import 'package:rume/seeker_module/booking_payment/all_transactions_history_page.dart';
import 'package:rume/seeker_module/booking_payment/transaction_receipt_page.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:intl/intl.dart'; 

class RentalPaymentPage extends StatefulWidget {
  const RentalPaymentPage({super.key});

  @override
  State<RentalPaymentPage> createState() => _RentalPaymentPageState();
}

class _RentalPaymentPageState extends State<RentalPaymentPage> {
  bool _isLoading = false;
  Map<String, dynamic>? _activeBooking;
  bool _hasActiveBooking = false;
  bool _isCheckingBooking = true;
  bool _isRentPaidThisMonth = false;
  bool _isCheckingRentStatus = true;

  @override
  void initState() {
    super.initState();
    _checkActiveBooking();
  }

  Future<void> _checkActiveBooking() async {
    debugPrint("🔄 [DEBUG] Checking for active booking...");
    if (!mounted) return;
    setState(() {
      _isCheckingBooking = true;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("❌ [DEBUG] User is not logged in.");
      if (mounted) setState(() => _isCheckingBooking = false);
      return;
    }

    try {
      final bookingSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('seekerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'booked')
          .limit(1)
          .get();

      if (bookingSnapshot.docs.isNotEmpty) {
        debugPrint("✅ [DEBUG] Active booking found!");
        final activeBookingData = bookingSnapshot.docs.first.data()
          ..['id'] = bookingSnapshot.docs.first.id;
        if (mounted) {
          setState(() {
            _hasActiveBooking = true;
            _activeBooking = activeBookingData;
          });
          await _checkCurrentMonthRentStatus(); 
        }
      } else {
        debugPrint("ℹ️ [DEBUG] No active booking found for this user.");
        if (mounted) {
          setState(() {
            _hasActiveBooking = false;
            _activeBooking = null;
            _isCheckingRentStatus = false;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('🛑 [DEBUG] Error checking active booking: $e');
    } finally {
      if (mounted) setState(() => _isCheckingBooking = false);
    }
  }

  Future<void> _checkCurrentMonthRentStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    final booking = _activeBooking;
    debugPrint("🔄 [DEBUG] Checking current month's rent status...");
    if (user == null || booking == null) {
      if (mounted) setState(() => _isCheckingRentStatus = false);
      return;
    }

    if (mounted) setState(() => _isCheckingRentStatus = true);

    try {
      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);
      final moveInDate = (booking['bookingDate'] as Timestamp?)?.toDate();

      debugPrint("  - Current Month Range: $currentMonthStart to $nextMonthStart");
      
      bool isFirstMonthAndPaid = false;
      if (moveInDate != null &&
          moveInDate.year == now.year &&
          moveInDate.month == now.month) {
        debugPrint("  - ℹ️ It's the move-in month, considering rent as paid.");
        isFirstMonthAndPaid = true;
      }

   
      final rentPaidThisMonth = await FirebaseFirestore.instance
          .collection("transactions")
          .where("userId", isEqualTo: user.uid)
          .where("status", isEqualTo: "succeeded")
          .where("paymentType", isEqualTo: "rent")
          .where(
            "bookingId",
            isEqualTo: booking['id'],
          ) 
          .where(
            "createdAt",
            isGreaterThanOrEqualTo: Timestamp.fromDate(currentMonthStart),
          )
          .where("createdAt", isLessThan: Timestamp.fromDate(nextMonthStart))
          .get();

      final bool hasPaid = rentPaidThisMonth.docs.isNotEmpty || isFirstMonthAndPaid;
      debugPrint("  - Firestore check found ${rentPaidThisMonth.docs.length} rent payment(s) this month.");
      debugPrint("  - ✅ Final rent status for this month: ${hasPaid ? 'PAID' : 'NOT PAID'}.");

      if (mounted) {
        setState(() {
          _isRentPaidThisMonth = hasPaid;
          _isCheckingRentStatus = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingRentStatus = false);
      if (kDebugMode) debugPrint("🛑 [DEBUG] Error checking rent status: $e");
    }
  }

  Future<Map<String, dynamic>> _getUserData(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!doc.exists) {
        throw Exception("User data not found.");
      }
      return doc.data()!;
    } catch (e) {
      if (kDebugMode) debugPrint('🛑 [DEBUG] Error fetching user data: $e');
      rethrow;
    }
  }


  int parseAmount(dynamic value) {
    if (value == null) return 0;
   
    if (value is int) return value * 100;
    if (value is double) return (value * 100).round();
    if (value is String) {
   
      final parsed = double.tryParse(value);
      if (parsed != null) return (parsed * 100).round();
    }
    return 0;
  }

  Future<void> _createCheckoutSession({
    required int amount,
    required String description,
    required String ownerId,
    required String propertyId,
    required String roomId,
  }) async {
    debugPrint("🔄 [DEBUG] Creating checkout session...");
    if (_isLoading) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User must be logged in.");

      final userData = await _getUserData(user.uid);

      
      final int rumeServiceFee = (amount * 0.01).round();

      final int totalAmount = ((amount + rumeServiceFee) / 0.975).round();
      final int paymongoFee = totalAmount - amount - rumeServiceFee;

      debugPrint("  - Base Amount: $amount cents");
      debugPrint("  - RuMe Service Fee: $rumeServiceFee cents");
      debugPrint("  - PayMongo Fee: $paymongoFee cents");
      debugPrint("  - Total Amount to Charge: $totalAmount cents");


      final url = Uri.parse(
        'https://createpaymongocheckoutsession-uvt3gqitdq-uc.a.run.app',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "email": userData['email'],
          "payerName": "${userData['firstName']} ${userData['lastName']}",
          "userId": user.uid,
          "ownerId": ownerId,
          "role": userData['role'],
          "totalAmount": totalAmount,
          "paymongoFee": paymongoFee,
          "rumeServiceFee": rumeServiceFee, 
          "description": description,
          "propertyId": propertyId,
          "roomId": roomId,
          "bookingId":
              _activeBooking?['id'], 
          "paymentType": "rent",
        }),
      );

      if (response.statusCode != 200) {
        debugPrint("  - 🛑 Checkout session failed. Status: ${response.statusCode}, Body: ${response.body}");
        throw Exception('Checkout session failed: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final checkoutUrl = data['checkoutUrl'] as String;

      debugPrint("  - ✅ Checkout URL received: $checkoutUrl");
      if (await canLaunchUrlString(checkoutUrl)) {
        await launchUrlString(
          checkoutUrl,
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw Exception('Could not launch payment URL.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().split(":").last.trim()}'),
          ),
        );
      }
      if (kDebugMode) debugPrint('🛑 [DEBUG] Error in createCheckoutSession: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createRentCheckoutSession() async {
    final user = FirebaseAuth.instance.currentUser;
    final booking = _activeBooking;
    if (user == null || booking == null) return;

    
    if (_isRentPaidThisMonth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Rent is already paid for this month.")),
      );
      return;
    }
    try {
      final int roomPriceInCentavos = parseAmount(booking['roomPrice']);
      final String propertyName = booking['propertyName'] ?? 'Property';
      final String roomName = booking['roomName'] ?? 'Room';

      await _createCheckoutSession(
        amount: roomPriceInCentavos,
        description: "Monthly Rent - $propertyName ($roomName)",
        ownerId: booking['ownerId'],
        propertyId: booking['propertyId'],
        roomId: booking['roomId'],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().split(":").last.trim()}'),
          ),
        );
      }
      if (kDebugMode) debugPrint('🛑 [DEBUG] Error creating rent checkout: $e');
    }
  }

  Widget _buildLockedView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Iconsax.house_2,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              'No Active Room',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Once you book a room, you can manage your monthly rental payments right here.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _getPaymentMethodAsset(String? method) {
    switch (method) {
      case 'gcash':
        return 'assets/payments/GCash.png';
      case 'PAYMAYA':
        return 'assets/payments/Paymaya.png';
      case 'grab_pay':
        return 'assets/payments/Grabpay.png';
      default:
      
        return 'assets/payments/Paymaya.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (_isCheckingBooking || _isCheckingRentStatus) {
      return const StandardLoadingScreen();
    }

    if (!_hasActiveBooking) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text("My Payments"),
          titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AllTransactionsHistoryPage(),
                  ),
                );
              },
              icon: const Icon(Iconsax.receipt_search, color: Colors.black45),
              tooltip: 'Transaction History',
            ),
          ],
        ),
        body: _buildLockedView(),
      );
    }

    final roomPrice = parseAmount(
      _activeBooking!['roomPrice'],
    );

   
    final int rumeServiceFee = (roomPrice * 0.01).round();
    final totalAmount = ((roomPrice + rumeServiceFee) / 0.975).round();
    final paymongoFee = totalAmount - roomPrice - rumeServiceFee;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("My Payments"),
        titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AllTransactionsHistoryPage(),
                ),
              );
            },
            icon: const Icon(Iconsax.receipt_search, color: Colors.black54),
            tooltip: 'Transaction History',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _checkActiveBooking,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.blueAccent)],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Iconsax.wallet_3,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "Monthly Rent",
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Settle your rent for the current month.",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 32, color: Colors.white.withOpacity(0.2)),
                      _buildPriceRow('Monthly Rent', roomPrice.toDouble()),
                      const SizedBox(height: 12),
                      _buildPriceRow(
                        'RuMe Service Fee',
                        rumeServiceFee.toDouble(),
                      ),
                      const SizedBox(height: 12),
                      _buildPriceRow(
                        'Paymongo Payment Service Fee',
                        paymongoFee.toDouble(),
                      ),
                      Divider(height: 32, color: Colors.white.withOpacity(0.2)),
                      _buildTotalRow('Total Amount', totalAmount.toDouble()),
                      const SizedBox(height: 32),
                      Container(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading || _isRentPaidThisMonth
                              ? null
                              : _createRentCheckoutSession,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: 3,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Iconsax.wallet_check, size: 22),
                                    const SizedBox(width: 10),
                                    Text(
                                      _isRentPaidThisMonth
                                          ? 'Paid This Month'
                                          : 'Proceed to Pay',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
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
             
              if (_activeBooking?['leaveRequestStatus'] == 'pending' &&
                  _activeBooking?['leavePaymentStatus'] != 'fully_paid') ...[
                const SizedBox(height: 24),
                _buildFinalSettlementCard(),
              ],
              const SizedBox(height: 24),
              Text(
                "Recent Transactions",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF2C2F4D),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              user == null
                  ? const Center(
                      child: Text(
                        "Login required to view transactions.",
                        style: TextStyle(color: AppColors.gray800),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection("transactions")
                          .where('userId', isEqualTo: user.uid)
                          .where('status', isEqualTo: 'succeeded')
                          .where(
                            'bookingId',
                            isEqualTo: _activeBooking?['id'],
                          )
                          .where(
                            'paymentType',
                            whereIn: ['rent', 'booking', 'final_payment'],
                          )
                          .orderBy("createdAt", descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 40,
                              horizontal: 20,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Iconsax.receipt_search,
                                  size: 50,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "No Transactions Yet",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Your successful payments will appear here.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                            final doc = snapshot.data!.docs[index];
                            final tx = doc.data() as Map<String, dynamic>;
                            final description =
                                tx['description'] ?? 'No description';
                            final int totalAmount = tx['totalAmount'] ?? 0;
                            final String? paymentMethod =
                                tx['method'] as String?;
                            final date = (tx['createdAt'] is Timestamp)
                                ? (tx['createdAt'] as Timestamp).toDate()
                                : null;

                            return Card(
                              elevation: 0,
                              color: Colors.white,
                              margin: const EdgeInsets.symmetric(vertical: 8.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TransactionReceiptPage(
                                        transactionData: tx,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          8.0,
                                        ),
                                        child: Image.asset(
                                          _getPaymentMethodAsset(paymentMethod),
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Icon(
                                                    Iconsax.receipt_2_1,
                                                    color: AppColors.primary,
                                                  ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              description,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            if (date != null)
                                              Text(
                                                DateFormat(
                                                  'MMM d, yyyy \'at\' h:mm a',
                                                ).format(date),
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        currencyFormatter.format(
                                          totalAmount / 100,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Roboto',
                                          color: AppColors.successGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.8)),
        ),
        Text(
          currencyFormatter.format(amount / 100),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            fontFamily: 'Roboto',
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildTotalRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          currencyFormatter.format(amount / 100),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  
  Widget _buildFinalSettlementCard() {
    final outstandingBalance =
        (_activeBooking?['outstandingBalance'] as int? ?? 0);
    final checkoutDate = (_activeBooking?['checkoutDate'] as Timestamp?)
        ?.toDate();
    final totalRentDue = (_activeBooking?['totalRentDueForStay'] as int? ?? 0);
    final totalRentPaid = (_activeBooking?['totalRentPaid'] as int? ?? 0);
    final progress = totalRentDue > 0
        ? (totalRentPaid / totalRentDue).clamp(0.0, 1.0)
        : 0.0;

    if (outstandingBalance <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.blue900],
        ),
        borderRadius: BorderRadius.all(Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Final Settlement",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (checkoutDate != null)
              Text(
                "You have a pending leave request for ${DateFormat('MMMM d, yyyy').format(checkoutDate)}. Settle your balance to complete the process.",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            Divider(height: 24, color: Colors.white.withOpacity(0.2)),
            
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
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
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.successGreen,
                  ),
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
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
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FinalPaymentPage(booking: _activeBooking!),
                    ),
                  );
                },
                icon: const Icon(Iconsax.wallet_check),
                label: Text(
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
                  shadowColor: Colors.black.withOpacity(0.2),
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
