

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iconsax/iconsax.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/seeker_module/booking_payment/booking_history_page.dart';
import 'package:rume/components/loading_screen.dart';
import 'package:rume/seeker_module/inquiries/seeker_chat.dart';
import 'package:rume/seeker_module/booking_payment/booking_payment.dart';
import 'package:rume/seeker_module/booking_payment/final_payment_page.dart';
import 'package:rume/seeker_module/feedback/view_feedback_dialog.dart';
import 'package:rume/seeker_module/feedback/feedback_dialog.dart';
import 'package:rume/utils/booking_helpers.dart';


class PropertyDetailsPage extends StatefulWidget {
  const PropertyDetailsPage({super.key});

  @override
  State<PropertyDetailsPage> createState() => _PropertyDetailsPageState();
}

class _PropertyDetailsPageState extends State<PropertyDetailsPage> {
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _isInitialLoad = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoad) return const StandardLoadingScreen();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'My Booking',
          style: TextStyle( 
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            fontFamily: 'Poppins',
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BookingHistoryPage(),
                ),
              );
            },
            icon: const Icon(Iconsax.direct_inbox, color: Colors.black54),
            tooltip: 'Booking History',
          ),
        ],
      ),
      body: const BookingsTab(), 
    );
  }
}

class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  final Map<String, UniqueKey> _feedbackKeys = {};
  
  Future<void> _cancelBooking(BuildContext context, String bookingId) async {
    final confirm = await BookingHelpers.showConfirmDialog(
      context: context,
      title: 'Cancel Booking',
      content: 'Are you sure you want to cancel this booking request?',
      confirmText: 'Yes, Cancel',
      confirmColor: Colors.red,
    );

    if (confirm == true) {
      final success = await BookingHelpers.deleteBooking(bookingId: bookingId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Booking cancelled successfully' 
                  : 'Failed to delete booking',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _proceedToPayment(
    BuildContext context,
    Map<String, dynamic> booking,
  ) async {
    final dynamic rawPrice = booking['roomPrice'] ?? 0;
    final int roomPrice = rawPrice is int
        ? rawPrice
        : (rawPrice as num).toInt();

    final bookingDate =
        (booking['bookingDate'] as Timestamp?)?.toDate() ?? DateTime.now();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookingPaymentPage(
          bookingId: booking['id'],
          roomPrice: roomPrice,
          propertyName: booking['propertyName'] ?? 'Property',
          roomName: booking['roomName'] ?? 'Room',
          propertyAddress: booking['propertyAddress'] ?? 'Address',
          moveInDate: bookingDate,
        ),
      ),
    );
  }

  Future<void> _inquireAboutProperty(
    BuildContext context,
    Map<String, dynamic> booking,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to start a chat'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final propertyId = booking['propertyId'];
      final ownerId = booking['ownerId'];
      final propertyName = booking['propertyName'] ?? 'Property';

      final chatQuery = await FirebaseFirestore.instance
          .collection('chats')
          .where('propertyId', isEqualTo: propertyId)
          .where('seekerId', isEqualTo: user.uid)
          .limit(1)
          .get();

      String chatId;
      if (chatQuery.docs.isEmpty) {
        final newChat =
            await FirebaseFirestore.instance.collection('chats').add({
          'ownerId': ownerId,
          'seekerId': user.uid,
          'propertyId': propertyId,
          'propertyName': propertyName,
          'propertyImageUrl': booking['propertyImageUrl'] ?? '',
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadByOwner': true,
          'unreadBySeeker': false,
        });
        chatId = newChat.id;
      } else {
        chatId = chatQuery.docs.first.id;
      }

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SeekerChatPage(chatId: chatId, ownerId: ownerId),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String?> _fetchPropertyImage(String propertyId) async {
    try {
      final propertyDoc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(propertyId)
          .get();

      if (propertyDoc.exists) {
        final data = propertyDoc.data();
        final verificationData =
            data?['verificationData'] as Map<String, dynamic>?;
        return verificationData?['propertyFrontUrl'] as String?;
      }
    } catch (e) {
      debugPrint('Error fetching property image: $e');
    }
    return null;
  }

  Future<List<String>> _fetchRoomImages(
    String propertyId,
    String roomId,
  ) async {
    try {
      final roomDoc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(propertyId)
          .collection('rooms')
          .doc(roomId)
          .get();

      if (roomDoc.exists) {
        final data = roomDoc.data();
        return List<String>.from(data?['images'] ?? []);
      }
    } catch (e) {
      debugPrint('Error fetching room images: $e');
    }
    return [];
  }

  Future<Map<String, String>> _fetchOwnerDetails(String ownerId) async {
    try {
      final ownerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerId)
          .get();

      if (ownerDoc.exists) {
        final data = ownerDoc.data()!;
        final firstName = data['firstName'] ?? '';
        final lastName = data['lastName'] ?? '';
        final imageUrl = data['profileImageUrl'] as String? ?? '';
        return {'name': '$firstName $lastName'.trim(), 'imageUrl': imageUrl};
      }
    } catch (e) {
      debugPrint('Error fetching owner details: $e');
    }
    return {'name': 'Unknown Owner', 'imageUrl': ''};
  }

  Future<DocumentSnapshot?> _fetchSubmittedFeedback(String bookingId) async {
    try {
      final feedbackDoc = await FirebaseFirestore.instance
          .collection('feedbacks')
          .doc(bookingId)
          .get();

      return feedbackDoc.exists ? feedbackDoc : null;
    } catch (e) {
      debugPrint('Error fetching feedback: $e');
      return null;
    }
  }

  void _showFeedbackDialog(
    BuildContext context,
    Map<String, dynamic> booking,
  ) async {
    final result = await showDialog(
      context: context,
      builder: (_) => FeedbackDialog(
        propertyId: booking['propertyId'],
        roomId: booking['roomId'],
        bookingId: booking['id'],
        ownerId: booking['ownerId'],
        propertyName: booking['propertyName'] ?? 'N/A',
        roomName: booking['roomName'] ?? 'N/A',
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _feedbackKeys[booking['id']] = UniqueKey();
      });
    }
  }

  void _showViewFeedbackDialog(
    BuildContext context,
    String bookingId,
    DocumentSnapshot feedbackDoc,
  ) async {
    final feedbackData = feedbackDoc.data() as Map<String, dynamic>;
    final result = await showDialog(
      context: context,
      builder: (_) => ViewFeedbackDialog(
        feedbackId: feedbackDoc.id,
        bookingId: bookingId,
        rating: (feedbackData['rating'] as num? ?? 0.0).toDouble(),
        description: feedbackData['description'] as String? ?? '',
        status: feedbackData['status'] as String? ?? 'pending',
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _feedbackKeys[bookingId] = UniqueKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please log in to view bookings'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('seekerId', isEqualTo: user.uid)
          .where('status', whereIn: ['pending', 'awaiting_payment', 'booked'])
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.calendar_remove, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No Bookings Yet',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold, 
                      fontFamily: 'Poppins'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your booking requests will appear here',
                  style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      fontFamily: 'Poppins'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), 
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final booking = doc.data() as Map<String, dynamic>;
            booking['id'] = doc.id;
            final status = booking['status'] ?? 'unknown';

            if (status == 'booked') {
              return FullBookingDetails(
                key: ValueKey(doc.id),
                doc: doc,
                feedbackKey:
                    _feedbackKeys[doc.id] ?? ValueKey('feedback_${doc.id}'),
                fetchRoomImages: _fetchRoomImages,
                fetchOwnerDetails: _fetchOwnerDetails,
                fetchSubmittedFeedback: _fetchSubmittedFeedback,
                onShowFeedbackDialog: (bookingData) =>
                    _showFeedbackDialog(context, bookingData),
                onShowViewFeedbackDialog: (bookingId, feedbackDoc) =>
                    _showViewFeedbackDialog(context, bookingId, feedbackDoc),
              );
            }

            return _buildCardBookingDetails(context, doc, booking, status);
          },
        );
      },
    );
  }

  Widget _buildCardBookingDetails(
    BuildContext context,
    QueryDocumentSnapshot doc,
    Map<String, dynamic> booking,
    String status,
  ) {
    final propertyId = booking['propertyId'] as String? ?? '';
    final numberOfOccupants = booking['numberOfOccupants'] ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect( 
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
            child: Stack(
              children: [
                FutureBuilder<String?>(
                  future: _fetchPropertyImage(propertyId),
                  builder: (context, imageSnapshot) {
                    if (imageSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return Container(
                        height: 180,
                        color: Colors.grey[200],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    final imageUrl = imageSnapshot.data;

                    if (imageUrl != null && imageUrl.isNotEmpty) {
                      return CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 180,
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 180,
                          color: Colors.grey[300],
                          child: const Icon(
                            Iconsax.house,
                            size: 60,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    }

                    return Container(
                      height: 180,
                      color: Colors.grey[300],
                      child: const Icon(
                        Iconsax.house,
                        size: 60,
                        color: Colors.grey,
                      ),
                    );
                  },
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: BookingHelpers.getStatusColor(status),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      BookingHelpers.getStatusText(status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking['propertyName'] ?? 'Property',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins', 
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(Iconsax.bag, booking['roomName'] ?? 'Room'),
                _buildInfoRow(
                  Iconsax.location,
                  booking['propertyAddress'] ?? 'Address',
                ),
                _buildInfoRow(
                  Iconsax.calendar_1,
                  booking['bookingDate'] != null
                      ? 'Move-in: ${DateFormat('MMM d, yyyy').format((booking['bookingDate'] as Timestamp).toDate())}'
                      : 'Date not set',
                ),
                _buildInfoRow(
                  Iconsax.people,
                  '$numberOfOccupants ${numberOfOccupants == 1 ? 'occupant' : 'occupants'}',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Iconsax.wallet_money, size: 18, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '₱${booking['roomPrice'] ?? 0} + ₱100 booking fee',
                          style: TextStyle(color: Colors.grey[700], fontFamily: 'Roboto'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (status == 'pending' || status == 'awaiting_payment') ...[
                  const Divider(height: 24),
                  if (status == 'awaiting_payment') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _proceedToPayment(context, booking),
                        icon: const Icon(Iconsax.wallet_check),
                        label: const Text('Pay Booking Fee'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _inquireAboutProperty(context, booking),
                      icon: const Icon(Iconsax.message_question),
                      label: const Text('Inquire about Property'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelBooking(context, doc.id),
                      icon: const Icon(Iconsax.close_circle),
                      label: const Text('Cancel Booking'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [ 
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  TextStyle(color: Colors.grey[700], fontFamily: 'Poppins'),
            ),
          ),
        ],
      ),
    );
  }
}






class _BookingPageData {
  final List<String> imageUrls;
  final Map<String, String> ownerDetails;
  final DocumentSnapshot? feedback;

  _BookingPageData({
    required this.imageUrls,
    required this.ownerDetails,
    this.feedback,
  });
}

class FullBookingDetails extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Key feedbackKey;
  final Future<List<String>> Function(String, String) fetchRoomImages;
  final Future<Map<String, String>> Function(String) fetchOwnerDetails;
  final Future<DocumentSnapshot?> Function(String) fetchSubmittedFeedback;
  final void Function(Map<String, dynamic>) onShowFeedbackDialog;
  final void Function(String, DocumentSnapshot) onShowViewFeedbackDialog;

  const FullBookingDetails({
    super.key,
    required this.doc,
    required this.feedbackKey,
    required this.fetchRoomImages,
    required this.fetchOwnerDetails,
    required this.fetchSubmittedFeedback,
    required this.onShowFeedbackDialog,
    required this.onShowViewFeedbackDialog,
  });

  @override
  State<FullBookingDetails> createState() => _FullBookingDetailsState();
}

class _FullBookingDetailsState extends State<FullBookingDetails> {
  late Future<_BookingPageData> _bookingDataFuture;
  bool _isProcessingLeaveRequest = false;

  @override
  void initState() {
    super.initState();
    _bookingDataFuture = _fetchAllBookingData();
  }

  
  Future<_BookingPageData> _fetchAllBookingData() async {
    final booking = widget.doc.data() as Map<String, dynamic>;
    final propertyId = booking['propertyId'] as String? ?? '';
    final roomId = booking['roomId'] as String? ?? '';
    final ownerId = booking['ownerId'] as String? ?? '';

    
    final results = await Future.wait([
      widget.fetchRoomImages(propertyId, roomId),
      widget.fetchOwnerDetails(ownerId),
      widget.fetchSubmittedFeedback(widget.doc.id),
    ]);

    return _BookingPageData(
      imageUrls: results[0] as List<String>,
      ownerDetails: results[1] as Map<String, String>,
      feedback: results[2] as DocumentSnapshot?,
    );
  }

  
  int _calculateTotalRentForStay(
    DateTime moveIn,
    DateTime checkOut,
    num roomPrice, 
  ) {
    if (checkOut.isBefore(moveIn)) return 0;

    double totalRent = 0;
    DateTime current = moveIn;

    
    
    while (!current.isAfter(checkOut)) {
      final daysInMonth = DateUtils.getDaysInMonth(current.year, current.month);
      final dailyRate = roomPrice.toDouble() / daysInMonth; 

      if (current.year == checkOut.year && current.month == checkOut.month) {
        
        
        final startDay = (current.year == moveIn.year && current.month == moveIn.month) ? moveIn.day : 1;
        final daysToPay = checkOut.day - startDay + 1;
        totalRent += daysToPay * dailyRate;
        break;
      } else {
        
        final startDay = current.day;
        final daysToPay = daysInMonth - startDay + 1;
        totalRent += daysToPay * dailyRate;
        current = DateTime(current.year, current.month + 1, 1);
      }
    }

    return (totalRent * 100).round(); 
  }

  
  Future<int> _getTotalPaidRent(String seekerId, String bookingId) async {
    final rentPaidSnapshot = await FirebaseFirestore.instance
        .collection("transactions")
        .where("userId", isEqualTo: seekerId) 
        .where("bookingId", isEqualTo: bookingId) 
        .where("status", isEqualTo: "succeeded") 
        .get();

    return rentPaidSnapshot.docs.fold<int>(0, (sum, doc) => sum + (doc.data()['amount'] as int? ?? 0)); 
  }

  
  Future<void> _requestToLeave(
    String bookingId,
    DateTime? currentCheckoutDate,
  ) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: currentCheckoutDate ?? DateTime.now().add(const Duration(days: 30)),
      
      firstDate: (widget.doc.data() as Map<String, dynamic>)['bookingDate'].toDate(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select your Checkout Date',
    );

    if (pickedDate == null || !mounted) return;

    final confirm = await BookingHelpers.showConfirmDialog(
      context: context,
      title: 'Request to Leave',
      content: currentCheckoutDate == null
          ? 'You are requesting to leave on ${DateFormat('MMMM d, yyyy').format(pickedDate)}. The owner will be notified to process your checkout. Continue?'
          : 'You are updating your checkout date to ${DateFormat('MMMM d, yyyy').format(pickedDate)}. Continue?',
      confirmText: 'Yes, Send Request',
      confirmColor: Colors.orange,
    );

    if (confirm != true) return;

    if (mounted) setState(() => _isProcessingLeaveRequest = true);
    try {
      final booking = widget.doc.data() as Map<String, dynamic>;
      final moveInDate = (booking['bookingDate'] as Timestamp).toDate();
      final roomPrice = booking['roomPrice'] as num; 
      final seekerId = booking['seekerId'] as String;

      
      final totalRentDue = _calculateTotalRentForStay(moveInDate, pickedDate, roomPrice);
      final totalRentPaid = await _getTotalPaidRent(seekerId, bookingId); 
      final outstandingBalance = totalRentDue - totalRentPaid;

      final leavePaymentStatus = outstandingBalance <= 0 ? 'fully_paid' : 'pending_payment';

      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({
            'leaveRequestStatus': 'pending',
            'leaveRequestAt': FieldValue.serverTimestamp(),
            'checkoutDate': Timestamp.fromDate(pickedDate),
            'updatedAt': FieldValue.serverTimestamp(),
            
            'totalRentDueForStay': totalRentDue,
            'totalRentPaid': totalRentPaid,
            'outstandingBalance': outstandingBalance,
            'leavePaymentStatus': leavePaymentStatus,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave request sent successfully!'),
            backgroundColor: Colors.green, 
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        );
        
        setState(() {
          _bookingDataFuture = _fetchAllBookingData();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send leave request: $e'),
            backgroundColor: Colors.red, 
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingLeaveRequest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: FutureBuilder<_BookingPageData>(
        future: _bookingDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _BookingDetailsSkeleton();
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text("No details found."));
          }

          final bookingData = snapshot.data!;
          final booking = widget.doc.data() as Map<String, dynamic>;
          booking['id'] = widget.doc.id;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImageHeader(
                context,
                booking,
                bookingData.imageUrls,
                bookingData.ownerDetails,
              ),
              const SizedBox(height: 24),
              _buildDetailsCard(
                context,
                booking,
                bookingData.ownerDetails['name'] ?? 'Unknown',
              ),
              const SizedBox(height: 24),
              
              _buildLeaveAction(context, booking),
              const SizedBox(height: 16),
              _buildFeedbackAction(context, booking, bookingData.feedback),
              const SizedBox(height: 16),
              const Divider(thickness: 1.5),
            ],
          );
        },
      ),
    );
  }

  Widget _buildImageHeader(
    BuildContext context,
    Map<String, dynamic> booking,
    List<String> images,
    Map<String, String> ownerDetails,
  ) {
    final ownerName = ownerDetails['name'] ?? '...';
    final ownerImageUrl = ownerDetails['imageUrl'] ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      child: Stack(
        children: [
          if (images.isNotEmpty)
            _RoomImageCarousel(images: images)
          else
            Container(
              height: 250, 
              color: Colors.grey[200],
              child: const Center(
                child: Icon(Icons.apartment, size: 60, color: Colors.grey),
              ),
            ),

          
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          
          Positioned(
            top: MediaQuery.of(context).padding.top > 0
                ? MediaQuery.of(context).padding.top
                : 16,
            left: 16,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.white,
                  backgroundImage: (ownerImageUrl.isNotEmpty)
                      ? CachedNetworkImageProvider(ownerImageUrl)
                      : null,
                  child: (ownerImageUrl.isEmpty) 
                      ? const Icon(Icons.person, color: Colors.grey, size: 28)
                      : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Property Owner',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Poppins', 
                      ),
                    ),
                    Text(
                      ownerName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking['propertyName'] ?? 'Property',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
                    fontFamily: 'Poppins',
                  ),
                ),
                Text(
                  booking['roomName'] ?? 'Room',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                    shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),

          
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min, 
                children: const [
                  Icon(Icons.check_circle, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'BOOKED',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12, 
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(
    BuildContext context,
    Map<String, dynamic> booking,
    String ownerName,
  ) {
    final numberOfOccupants = booking['numberOfOccupants'] ?? 1;
    final moveInDate = booking['bookingDate'] != null
        ? DateFormat(
            'MMMM d, yyyy',
          ).format((booking['bookingDate'] as Timestamp).toDate())
        : 'Date not set';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            "Booking Information",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          _buildDetailRow(
            Iconsax.wallet_money,
            'Monthly Rent',
            '₱${booking['roomPrice'] ?? 0}',
          ),
          _buildDetailRow(
            Iconsax.people,
            'Occupants',
            '$numberOfOccupants ${numberOfOccupants == 1 ? 'person' : 'persons'}',
          ),
          _buildDetailRow(
            Iconsax.calendar_1,
            'Move-in Date',
            moveInDate,
          ),
          _buildDetailRow(
            Iconsax.location,
            'Address',
            booking['propertyAddress'] ?? 'Not provided',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Icon(icon, color: AppColors.primaryColor, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                    fontFamily: 'Poppins', 
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto', 
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackAction(
    BuildContext context,
    Map<String, dynamic> booking,
    DocumentSnapshot? feedback,
  ) {
    final moveInDate = (booking['bookingDate'] as Timestamp).toDate();
    final canLeaveFeedback = DateTime.now().isAfter(moveInDate);
    final hasGivenFeedback = feedback != null;

    if (canLeaveFeedback && !hasGivenFeedback) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => widget.onShowFeedbackDialog(booking), 
          icon: const Icon(Iconsax.message_edit),
          label: const Text('Leave Feedback'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins', 
            ),
          ),
        ),
      );
    }

    if (hasGivenFeedback) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () =>
              widget.onShowViewFeedbackDialog(widget.doc.id, feedback), 
          icon: const Icon(Iconsax.eye),
          label: const Text('View Your Feedback'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primaryColor, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins', 
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.info_circle, color: AppColors.primaryColor),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'You can leave feedback after your move-in date.',
              style: TextStyle(
                color: AppColors.primaryColor,
                fontWeight: FontWeight.w500,
                fontFamily: 'Poppins', 
              ),
            ),
          ),
        ],
      ),
    );
  }

  
  Widget _buildLeaveAction(BuildContext context, Map<String, dynamic> booking) {
    final leaveStatus = booking['leaveRequestStatus'] as String?;
    final checkoutDate = (booking['checkoutDate'] as Timestamp?)?.toDate();
    final leavePaymentStatus = booking['leavePaymentStatus'] as String?;

    if (leaveStatus == 'pending' && checkoutDate != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: _buildLeaveStatusContent(
            context, booking, checkoutDate, leavePaymentStatus),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isProcessingLeaveRequest
            ? null
            : () => _requestToLeave(booking['id'], null),
        icon: _isProcessingLeaveRequest
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Iconsax.logout),
        label:
            Text(_isProcessingLeaveRequest ? 'Sending...' : 'Request to Leave'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins'), 
        ),
      ),
    );
  }

  
  Widget _buildLeaveStatusContent(
    BuildContext context,
    Map<String, dynamic> booking,
    DateTime checkoutDate,
    String? leavePaymentStatus,
  ) {
    final outstandingBalance = (booking['outstandingBalance'] as int? ?? 0);
    final totalRentDue = (booking['totalRentDueForStay'] as int? ?? 0);
    final totalRentPaid = (booking['totalRentPaid'] as int? ?? 0);
    final progress = totalRentDue > 0 ? (totalRentPaid / totalRentDue).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [ 
            Icon(Icons.info_outline, color: Colors.orange[800]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Leave Request Pending',
                style: TextStyle(
                  color: Colors.orange[800],
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  fontSize: 16, 
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Your requested checkout date is ${DateFormat('MMMM d, yyyy').format(checkoutDate)}. The owner will be notified.',
          style: TextStyle(
              color: Colors.orange[700], height: 1.4, fontFamily: 'Poppins'),
        ),
        const Divider(height: 24),
        if (leavePaymentStatus == 'pending_payment' &&
            outstandingBalance > 0) ...[
          
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Payment Progress',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[800],
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.orange.withOpacity(0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Paid: ₱${(totalRentPaid / 100).toStringAsFixed(2)}',
                    style: const TextStyle(fontFamily: 'Roboto', color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Total Due: ₱${(totalRentDue / 100).toStringAsFixed(2)}',
                    style: const TextStyle(fontFamily: 'Roboto', color: Colors.black87),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FinalPaymentPage(booking: booking),
                  ), 
                );
              },
              icon: const Icon(Icons.payment),
              label: const Text('Pay Balance Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ] else if (leavePaymentStatus == 'fully_paid') ...[
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'You are fully paid. Waiting for owner to confirm checkout.',
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: _isProcessingLeaveRequest
                ? null 
                : () => _requestToLeave(booking['id'], checkoutDate),
            icon: const Icon(Icons.edit_calendar_outlined, size: 20),
            label: const Text('Update Checkout Date'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange[900],
              textStyle: const TextStyle(fontFamily: 'Poppins'),
            ),
          ),
        )
      ],
    );
  }
}


class _BookingDetailsSkeleton extends StatelessWidget {
  const _BookingDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 250,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ],
    );
  }
}


class _RoomImageCarousel extends StatefulWidget {
  final List<String> images;

  const _RoomImageCarousel({required this.images});

  @override
  State<_RoomImageCarousel> createState() => _RoomImageCarouselState();
}

class _RoomImageCarouselState extends State<_RoomImageCarousel> {
  int _currentPage = 0;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250, 
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemCount: widget.images.length,
            itemBuilder: (context, index) {
              return CachedNetworkImage(
                imageUrl: widget.images[index],
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[300],
                  child: const Icon(
                    Icons.error_outline,
                    size: 60,
                    color: Colors.grey,
                  ),
                ),
              );
            },
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.images.length,
                  (index) => AnimatedContainer(
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
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}