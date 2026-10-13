import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/components/currency.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:intl/intl.dart';

class FinalPaymentPage extends StatefulWidget {
  final Map<String, dynamic> booking;

  const FinalPaymentPage({
    super.key,
    required this.booking,
  });

  @override
  State<FinalPaymentPage> createState() => _FinalPaymentPageState();
}

class _FinalPaymentPageState extends State<FinalPaymentPage> {
  bool _isProcessing = false;
  late Future<List<Map<String, dynamic>>> _monthlyBreakdownFuture;

  @override
  void initState() {
    super.initState();
    _monthlyBreakdownFuture = _generateMonthlyBreakdown();
  }

  
  int _getDaysInMonth(int year, int month) {
    return DateUtils.getDaysInMonth(year, month);
  }

  

  Future<Map<String, dynamic>> _getUserData(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) throw Exception("User data not found.");
      return doc.data()!;
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      rethrow;
    }
  }

  
  Future<List<Map<String, dynamic>>> _generateMonthlyBreakdown() async {
    final moveInDate = (widget.booking['bookingDate'] as Timestamp).toDate();
    final checkoutDate = (widget.booking['checkoutDate'] as Timestamp).toDate();
    final roomPrice = (widget.booking['roomPrice'] as num).toDouble();
    final seekerId = widget.booking['seekerId'];

    
    final rentPaidSnapshot = await FirebaseFirestore.instance
        .collection("transactions")
        .where("userId", isEqualTo: seekerId)
        .where("bookingId", isEqualTo: widget.booking['id']) 
        .where("status", isEqualTo: "succeeded") 
        .where("paymentType", whereIn: ["rent", "booking"])
        .get();

    final paidMonths = <String>{}; 
    for (var doc in rentPaidSnapshot.docs) {
      final paidAt = (doc.data()['createdAt'] as Timestamp).toDate();
      paidMonths.add(DateFormat('yyyy-MM').format(paidAt));
    }

    final List<Map<String, dynamic>> breakdown = [];
    DateTime current = moveInDate;

    
    
    while (!current.isAfter(checkoutDate)) {
      final monthKey = DateFormat('yyyy-MM').format(current);
      final daysInMonth = _getDaysInMonth(current.year, current.month);
      final dailyRate = roomPrice / daysInMonth;
      int rentAmountCents = 0;

      if (current.year == moveInDate.year && current.month == moveInDate.month) {
        
        final daysToPay = daysInMonth - moveInDate.day + 1;
        rentAmountCents = (daysToPay * dailyRate * 100).round();
      } else if (current.year == checkoutDate.year && current.month == checkoutDate.month) {
        
        
        
        final daysToPay = checkoutDate.day; 
        rentAmountCents = (daysToPay * dailyRate * 100).round();
      } else {
        
        rentAmountCents = (roomPrice * 100).round();
      }

      
      final isMoveInMonth =
          current.year == moveInDate.year && current.month == moveInDate.month;
      
      
      final isPaid = isMoveInMonth || paidMonths.contains(monthKey);

      breakdown.add({
        'month': DateFormat('MMMM yyyy').format(current),
        'amount': rentAmountCents,
        'isPaid': isPaid,
      });

      
      current = DateTime(current.year, current.month + 1, 1);
    }


    if (breakdown.isEmpty && moveInDate.year == checkoutDate.year && moveInDate.month == checkoutDate.month) {
      final daysToPay = checkoutDate.difference(moveInDate).inDays + 1;
      final dailyRate = roomPrice / _getDaysInMonth(moveInDate.year, moveInDate.month);
      final rentAmountCents = (daysToPay * dailyRate * 100).round();

      breakdown.add({
        'month': DateFormat('MMMM yyyy').format(moveInDate),
        'amount': rentAmountCents,
        'isPaid': true, 
      });
    }


    return breakdown;
  }

  Future<void> _processFinalPayment() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User must be logged in.");

      final userData = await _getUserData(user.uid);

      final int outstandingBalance = widget.booking['outstandingBalance'] ?? 0;
      if (outstandingBalance <= 0) {
        throw Exception("No outstanding balance to pay.");
      }

    
      if (widget.booking['leavePaymentStatus'] == 'fully_paid') {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Your balance is already fully paid.")));
        return;
      }

      final int rumeServiceFee = (outstandingBalance * 0.01).round(); 
      final int grossAmount = outstandingBalance + rumeServiceFee;
      final int totalAmount = (grossAmount / 0.975).round();
      final int paymongoFee = totalAmount - outstandingBalance - rumeServiceFee;

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
          "ownerId": widget.booking['ownerId'],
          "role": userData['role'],
          "totalAmount": totalAmount,
          "paymongoFee": paymongoFee,
          "rumeServiceFee": rumeServiceFee, 
          "description": "Final Rent Settlement - ${widget.booking['propertyName']}",
          "propertyId": widget.booking['propertyId'],
          "bookingId": widget.booking['id'],
          "roomId": widget.booking['roomId'],
          "paymentType": "final_payment", 
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Checkout session failed: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final checkoutUrl = data['checkoutUrl'] as String;

      if (await canLaunchUrlString(checkoutUrl)) {
        await launchUrlString(checkoutUrl, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch payment URL.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().split(':').last.trim()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int totalRentDue = widget.booking['totalRentDueForStay'] ?? 0;
    final int totalRentPaid = widget.booking['totalRentPaid'] ?? 0;
    final int outstandingBalance = widget.booking['outstandingBalance'] ?? 0;

    
    final int rumeServiceFee = (outstandingBalance * 0.01).round();
    final int grossAmount = outstandingBalance + rumeServiceFee;
    final int totalAmountToPay = (grossAmount / 0.975).round();
    final int paymongoFee = totalAmountToPay - grossAmount;

    final moveInDate = (widget.booking['bookingDate'] as Timestamp).toDate();
    final checkoutDate = (widget.booking['checkoutDate'] as Timestamp).toDate();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Final Payment",
          style: TextStyle(color: AppColors.blue900, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            
            _buildMonthlyBreakdownCard(),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Payment Summary',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'For your stay from ${DateFormat('MMM d, yyyy').format(moveInDate)} to ${DateFormat('MMM d, yyyy').format(checkoutDate)}.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const Divider(height: 32),
                    _buildPriceRow('Total Rent Due', totalRentDue.toDouble(), false),
                    const SizedBox(height: 8),
                    _buildPriceRow('Total Rent Paid', -totalRentPaid.toDouble(), false),
                    const Divider(height: 24),
                    _buildPriceRow('Outstanding Balance', outstandingBalance.toDouble(), true),
                    const SizedBox(height: 8),
                    _buildPriceRow('RuMe Service Fee', rumeServiceFee.toDouble(), false),
                    const SizedBox(height: 8),
                    _buildPriceRow('Payment Gateway Fee', paymongoFee.toDouble(), false),
                    const Divider(height: 24, thickness: 2),
                    _buildPriceRow('Total Amount to Pay', totalAmountToPay.toDouble(), true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _processFinalPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.payment, color: Colors.white),
                          const SizedBox(width: 12),
                          Text(
                            'Pay Final Balance - ${currencyFormatter.format(totalAmountToPay / 100)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Roboto',
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  
  Widget _buildMonthlyBreakdownCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly Rent Breakdown',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _monthlyBreakdownFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No breakdown available.'));
                }

                final breakdown = snapshot.data!;
                return Column(
                  children: breakdown.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  item['isPaid']
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: item['isPaid']
                                      ? Colors.green
                                      : Colors.grey,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  item['month'],
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    decoration: item['isPaid']
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                    color: item['isPaid']
                                        ? Colors.grey[600]
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            currencyFormatter.format(item['amount'] / 100),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Roboto',
                              decoration: item['isPaid']
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              color: item['isPaid']
                                  ? Colors.grey[600]
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, double amount, bool isTotal) {
    final bool isNegative = amount < 0;
    final Color amountColor = isNegative
        ? Colors.red
        : (isTotal ? Colors.green[700]! : Colors.black87);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 18 : 15,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? AppColors.blue900 : Colors.black87,
          ),
        ),
        Text(
          '${isNegative ? '-' : ''}${currencyFormatter.format(amount.abs() / 100)}',
          style: TextStyle(
            fontSize: isTotal ? 20 : 16,
            fontWeight: FontWeight.bold,
            color: amountColor,
            fontFamily: 'Roboto',
          ),
        ),
      ],
    );
  }
}