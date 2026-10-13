
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/owner_module/inquiries/owner_chat.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class RoomOccupantDetailsPage extends StatefulWidget {
  final String bookingId;
  final String propertyId;
  final String roomId;
  final Map<String, dynamic> bookingData;

  const RoomOccupantDetailsPage({
    super.key,
    required this.bookingId,
    required this.propertyId,
    required this.roomId,
    required this.bookingData,
  });

  @override
  State<RoomOccupantDetailsPage> createState() =>
      _RoomOccupantDetailsPageState();
}

class _RoomOccupantDetailsPageState extends State<RoomOccupantDetailsPage> {
  bool _isProcessing = false;

  Future<Map<String, dynamic>?> _fetchRoomData() async {
    try {
      final roomDoc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .doc(widget.roomId)
          .get();

      if (roomDoc.exists) {
        return roomDoc.data();
      }
    } catch (e) {
      debugPrint('Error fetching room data: $e');
    }
    return null;
  }

  Future<bool> _isRentPaidThisMonth(String seekerId) async {
    try {
      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);

      
      final moveInDate = (widget.bookingData['bookingDate'] as Timestamp?)
          ?.toDate();
      if (moveInDate != null &&
          moveInDate.year == now.year &&
          moveInDate.month == now.month) {
        return true; 
      }

      final rentPaidSnapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: seekerId)
          .where('bookingId', isEqualTo: widget.bookingId)
          .where('status', isEqualTo: 'succeeded')
          .where('paymentType', isEqualTo: 'rent')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(currentMonthStart),
          )
          .where('createdAt', isLessThan: Timestamp.fromDate(nextMonthStart))
          .limit(1)
          .get();

      return rentPaidSnapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking rent payment: $e');
      return false;
    }
  }

  int _calculateOverdueDays() {
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    return now.difference(firstOfMonth).inDays;
  }

  Future<void> _checkoutOccupant() async {
    if (widget.bookingData['leaveRequestStatus'] != 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A leave request from the seeker is required for checkout.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    
    final leavePaymentStatus = widget.bookingData['leavePaymentStatus'];
    if (leavePaymentStatus != 'fully_paid') {
      final outstandingBalance =
          (widget.bookingData['outstandingBalance'] as int? ?? 0);

      final snackBar = SnackBar(
        elevation: 0,

        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        content: AwesomeSnackbarContent(
          title: 'Checkout Blocked',
          message:
              'Cannot checkout. Outstanding balance: ₱${(outstandingBalance / 100).toStringAsFixed(2)}',
          contentType: ContentType.failure,
          titleTextStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
          messageTextStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15,
            color: Colors.white,
          ),
        ),
        duration: const Duration(seconds: 4),
      );

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(snackBar);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Iconsax.logout, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Approve Checkout'),
          ],
        ),
        content: const Text(
          'The seeker has fully paid their balance. Do you want to approve this checkout?\n\n'
          'This will:\n'
          '• Set the room status back to "Available"\n'
          '• Mark the booking as "Checked Out"\n'
          '• Allow new bookings for this room\n\n'
          'This action cannot be undone.',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Approve Checkout',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .doc(widget.roomId)
          .update({
            'status': 'available',
            'updatedAt': FieldValue.serverTimestamp(),
          });

      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .update({
            'status': 'checked_out',
            'checkedOutAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Occupant checked out successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to checkout occupant: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openChat() async {
    try {
      final seekerId = widget.bookingData['seekerId'];
      if (seekerId == null) return;

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final chatQuery = await FirebaseFirestore.instance
          .collection('chats')
          .where('propertyId', isEqualTo: widget.propertyId)
          .where('ownerId', isEqualTo: currentUser.uid)
          .where('seekerId', isEqualTo: seekerId)
          .limit(1)
          .get();

      String chatId;
      if (chatQuery.docs.isEmpty) {
        final newChat = await FirebaseFirestore.instance
            .collection('chats')
            .add({
              'ownerId': currentUser.uid,
              'seekerId': seekerId,
              'propertyId': widget.propertyId,
              'propertyName': widget.bookingData['propertyName'] ?? '',
              'propertyImageUrl': widget.bookingData['propertyImageUrl'] ?? '',
              'lastMessage': '',
              'lastMessageTime': FieldValue.serverTimestamp(),
              'unreadByOwner': false,
              'unreadBySeeker': false,
            });
        chatId = newChat.id;
      } else {
        chatId = chatQuery.docs.first.id;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OwnerChatPage(chatId: chatId, seekerId: seekerId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  int _calculateAge(Timestamp? dateOfBirth) {
    if (dateOfBirth == null) return 0;
    final dob = dateOfBirth.toDate();
    final today = DateTime.now();
    int age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final age = _calculateAge(widget.bookingData['seekerDateOfBirth']);
    final leaveRequestStatus = widget.bookingData['leaveRequestStatus'];
    final leavePaymentStatus = widget.bookingData['leavePaymentStatus'];
    final checkoutDate = (widget.bookingData['checkoutDate'] as Timestamp?)
        ?.toDate();
    final outstandingBalance =
        (widget.bookingData['outstandingBalance'] as int? ?? 0);
    final seekerId = widget.bookingData['seekerId'];
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Online Occupant',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),

        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchRoomData(),
        builder: (context, roomSnapshot) {
          if (roomSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final roomData = roomSnapshot.data;
          final images = roomData != null
              ? List<String>.from(roomData['images'] ?? [])
              : <String>[];

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ImageCarousel(images: images),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.bookingData['roomName'] ?? 'Room',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'OCCUPIED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Iconsax.wallet_money,
                            size: 20,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '₱${widget.bookingData['roomPrice'] ?? 0}/month',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      
                      if (leaveRequestStatus == 'pending' &&
                          checkoutDate != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.orange[100]!, Colors.orange[50]!],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange[300]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Iconsax.info_circle,
                                    color: Colors.orange[800],
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Leave Request Pending',
                                      style: TextStyle(
                                        color: Colors.orange[900],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                Iconsax.calendar_1,
                                'Checkout Date',
                                DateFormat('MMMM d, yyyy').format(checkoutDate),
                                color: Colors.orange[900]!,
                              ),
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                Iconsax.wallet_3,
                                'Remaining Balance',
                                '₱${(outstandingBalance / 100).toStringAsFixed(2)}',
                                color: leavePaymentStatus == 'fully_paid'
                                    ? Colors.green[700]!
                                    : Colors.red[700]!,
                              ),
                              if (leavePaymentStatus == 'fully_paid') ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      Iconsax.tick_circle,
                                      color: Colors.green[700],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Fully Paid - Ready to Checkout',
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      
                      const Text(
                        'Current Occupant',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundImage:
                                        widget.bookingData['seekerImageUrl'] !=
                                            null
                                        ? CachedNetworkImageProvider(
                                            widget
                                                .bookingData['seekerImageUrl'],
                                          )
                                        : null,
                                    child:
                                        widget.bookingData['seekerImageUrl'] ==
                                            null
                                        ? const Icon(Iconsax.user, size: 30)
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.bookingData['seekerName'] ??
                                              'Seeker',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${age > 0 ? '$age years old' : 'Age N/A'} • ${widget.bookingData['seekerGender'] ?? 'N/A'}',
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
                              const Divider(height: 24),
                              _buildInfoRow(
                                Iconsax.sms,
                                'Email',
                                widget.bookingData['seekerEmail'] ?? 'N/A',
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                Iconsax.calendar,
                                'Date Moved In',
                                widget.bookingData['bookingDate'] != null
                                    ? DateFormat('MMMM d, yyyy').format(
                                        (widget.bookingData['bookingDate']
                                                as Timestamp)
                                            .toDate(),
                                      )
                                    : 'N/A',
                              ),
                              const SizedBox(height: 12),
                              
                              FutureBuilder<bool>(
                                future: _isRentPaidThisMonth(seekerId),
                                builder: (context, rentSnapshot) {
                                  if (rentSnapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    );
                                  }

                                  final isPaid = rentSnapshot.data ?? false;
                                  final overdueDays = isPaid
                                      ? 0
                                      : _calculateOverdueDays();

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isPaid
                                          ? Colors.green[50]
                                          : Colors.red[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isPaid
                                            ? Colors.green[200]!
                                            : Colors.red[200]!,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isPaid
                                              ? Iconsax.tick_circle
                                              : Iconsax.close_circle,
                                          color: isPaid
                                              ? Colors.green[700]
                                              : Colors.red[700],
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                isPaid
                                                    ? 'Rent Paid This Month'
                                                    : 'Rent Not Paid',
                                                style: TextStyle(
                                                  color: isPaid
                                                      ? Colors.green[900]
                                                      : Colors.red[900],
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if (!isPaid && overdueDays > 0)
                                                Text(
                                                  '$overdueDays ${overdueDays == 1 ? 'day' : 'days'} overdue',
                                                  style: TextStyle(
                                                    color: Colors.red[700],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _openChat,
                                  icon: const Icon(Iconsax.message),
                                  label: const Text('Chat Tenant'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(
                                      color: AppColors.primary,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      
                      const Text(
                        'Payment Timeline',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (currentUser != null)
                        _buildPaymentTimeline(currentUser.uid),
                      const SizedBox(height: 24),

                      
                      const Text(
                        'Feedback',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFeedbackSection(),
                      const SizedBox(height: 32),

                      
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _checkoutOccupant,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Iconsax.logout, color: Colors.white),
                          label: Text(
                            _isProcessing
                                ? 'Processing...'
                                : leaveRequestStatus == 'pending'
                                ? 'Approve Checkout'
                                : 'Checkout Occupant',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey[600]),
        const SizedBox(width: 12),
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
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: color ?? Colors.black87,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentTimeline(String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .where('ownerId', isEqualTo: currentUserId)
          .where('bookingId', isEqualTo: widget.bookingId)
          .where('status', isEqualTo: 'succeeded')
          .where('paymentType', whereIn: ['rent', 'booking', 'final_payment'])
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Iconsax.receipt_minus,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No payment history yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final payments = snapshot.data!.docs;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: payments.length,
              separatorBuilder: (context, index) => Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 30,
                width: 2,
                color: Colors.green[200],
                child: const SizedBox(width: 2),
              ),
              itemBuilder: (context, index) {
                final payment = payments[index].data() as Map<String, dynamic>;
                final totalAmount = (payment['totalAmount'] ?? 0) / 100;
                final amount = (payment['amount'] ?? 0) / 100;
                final serviceFee = (payment['rumeServiceFee'] ?? 0) / 100;
                final paymongoFee = (payment['paymongoFee'] ?? 0) / 100;
                final date = payment['createdAt'] != null
                    ? (payment['createdAt'] as Timestamp).toDate()
                    : null;
                final paymentType = payment['paymentType'] ?? 'rent';

                String typeLabel;
                IconData typeIcon;
                Color typeColor;

                switch (paymentType) {
                  case 'booking':
                    typeLabel = 'Booking Payment';
                    typeIcon = Iconsax.ticket;
                    typeColor = Colors.blue;
                    break;
                  case 'final_payment':
                    typeLabel = 'Final Settlement';
                    typeIcon = Iconsax.wallet_check;
                    typeColor = Colors.orange;
                    break;
                  default:
                    typeLabel = 'Rent Payment';
                    typeIcon = Iconsax.wallet_money;
                    typeColor = Colors.green;
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: typeColor, width: 2),
                      ),
                      child: Icon(typeIcon, color: typeColor, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            typeLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (date != null)
                            Text(
                              DateFormat('MMMM d, yyyy • h:mm a').format(date),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Column(
                              children: [
                                _buildPaymentRow('Amount', amount),
                                const Divider(height: 16),
                                _buildPaymentRow('Service Fee', serviceFee),
                                _buildPaymentRow('Gateway Fee', paymongoFee),
                                const Divider(height: 16),
                                _buildPaymentRow(
                                  'Total',
                                  totalAmount,
                                  isBold: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentRow(String label, double amount, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Roboto',
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? Colors.green[700] : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackSection() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(widget.bookingId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Iconsax.message_minus,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No feedback yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Feedback from the occupant will appear here',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final feedbackData = snapshot.data!.data() as Map<String, dynamic>;
        final rating = (feedbackData['rating'] as num?)?.toDouble() ?? 0.0;
        final description = feedbackData['description'] as String? ?? '';
        final createdAt = (feedbackData['createdAt'] as Timestamp?)?.toDate();

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(5, (index) {
                    return Icon(
                      index < rating ? Iconsax.star1 : Iconsax.star,
                      color: index < rating ? Colors.amber : Colors.grey[300],
                      size: 20,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[800],
                    height: 1.5,
                  ),
                ),
                if (createdAt != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Iconsax.calendar, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('MMMM d, yyyy').format(createdAt),
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}


class _ImageCarousel extends StatefulWidget {
  final List<String> images;
  const _ImageCarousel({required this.images});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final images = widget.images;

    if (images.isEmpty) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.grey[300]!, Colors.grey[200]!],
          ),
        ),
        child: const Center(
          child: Icon(Icons.bed, size: 60, color: Colors.grey),
        ),
      );
    }

    return Stack(
      children: [
        SizedBox(
          height: 250,
          child: PageView.builder(
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: images.length,
            itemBuilder: (context, index) {
              return CachedNetworkImage(
                imageUrl: images[index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: 250,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (images.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Colors.white
                        : Colors.white54,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        if (images.length > 1)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentPage + 1}/${images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}