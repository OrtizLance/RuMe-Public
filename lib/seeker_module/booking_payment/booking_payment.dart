import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/components/currency.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:intl/intl.dart';

class BookingPaymentPage extends StatefulWidget {
  final String bookingId;
  final int roomPrice;
  final String propertyName;
  final String roomName;
  final String propertyAddress;
  final DateTime moveInDate;

  const BookingPaymentPage({
    super.key,
    required this.bookingId,
    required this.roomPrice,
    required this.propertyName,
    required this.roomName,
    required this.propertyAddress,
    required this.moveInDate,
  });

  @override
  State<BookingPaymentPage> createState() => _BookingPaymentPageState();
}

class _BookingPaymentPageState extends State<BookingPaymentPage> {
  bool _isProcessing = false;

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
      debugPrint('Error fetching user data: $e');
      rethrow;
    }
  }

  Future<void> _processBookingPayment() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User must be logged in.");
      }

      
      final bookingDoc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();

      if (!bookingDoc.exists) {
        throw Exception("Booking not found.");
      }

      final bookingData = bookingDoc.data()!;
      final ownerId = bookingData['ownerId'];
      final propertyId = bookingData['propertyId'];
      final roomId = bookingData['roomId'];

      final userData = await _getUserData(user.uid);

      
      final moveIn = widget.moveInDate;
      final daysInMonth = DateUtils.getDaysInMonth(moveIn.year, moveIn.month);
      final remainingDays = daysInMonth - moveIn.day + 1;

      
      final double dailyRate = (widget.roomPrice * 100) / daysInMonth;
      final int proratedRoomPriceInCentavos = (dailyRate * remainingDays).round();

      
      
      
      const int rumeServiceFee = 10000; 
      final int totalAmount = ((proratedRoomPriceInCentavos + rumeServiceFee) / 0.975).round();
      final int paymongoFee = totalAmount - proratedRoomPriceInCentavos - rumeServiceFee;

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
          "description":
              "Room Booking Payment - ${widget.propertyName} (${widget.roomName})",
          "propertyId": propertyId,
          "bookingId": widget.bookingId,
          "roomId": roomId,
          "paymentType": "booking",
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Checkout session failed: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final checkoutUrl = data['checkoutUrl'] as String;

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
    
    final moveIn = widget.moveInDate;
    final daysInMonth = DateUtils.getDaysInMonth(moveIn.year, moveIn.month);
    final remainingDays = daysInMonth - moveIn.day + 1;

    
    final double dailyRate = (widget.roomPrice * 100) / daysInMonth;
    final int proratedRoomPriceInCentavos = (dailyRate * remainingDays).round();

    
    const int rumeServiceFee = 10000; 
    final int totalAmount = ((proratedRoomPriceInCentavos + rumeServiceFee) / 0.975).round();
    final int paymongoFee = totalAmount - proratedRoomPriceInCentavos - rumeServiceFee;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Booking Payment",
          style: TextStyle(
            color: AppColors.blue900,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.propertyName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.blue900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.roomName,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      Icons.location_on,
                      'Address',
                      widget.propertyAddress,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.calendar_today,
                      'Move-in Date',
                      DateFormat('MMMM d, yyyy').format(widget.moveInDate),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Breakdown',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.blue900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPriceRow(
                        'Pro-rated Room Price ($remainingDays / $daysInMonth days)', proratedRoomPriceInCentavos.toDouble(), false),
                    const SizedBox(height: 8),
                    _buildPriceRow(
                        'RuMe Service Fee', rumeServiceFee.toDouble(), false),
                    const SizedBox(height: 8),
                    _buildPriceRow('Payment Gateway Fee', paymongoFee.toDouble(), false),
                    const Divider(height: 24, thickness: 2),
                    _buildPriceRow('Total Amount', totalAmount.toDouble(), true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Important Notice',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'To secure your reservation, a one-time booking fee is required. This includes a ₱100 platform fee and a payment processing fee.',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _processBookingPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: _isProcessing
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.payment, color: Colors.white),
                          const SizedBox(width: 12),
                          Text(
                            'Proceed to Payment - ${currencyFormatter.format(totalAmount / 100)}',
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

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(String label, double amount, bool isTotal) {
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
          currencyFormatter.format(amount / 100),
          style: TextStyle(
            fontSize: isTotal ? 20 : 16,
            fontWeight: FontWeight.bold,
            color: isTotal ? Colors.green[700] : Colors.black87,
            fontFamily: 'Roboto',
          ),
        ),
      ],
    );
  }
}
