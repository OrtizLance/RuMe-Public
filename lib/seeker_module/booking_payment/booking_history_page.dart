import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/utils/booking_helpers.dart';
import 'package:rume/seeker_module/booking_payment/booking_transaction_history_page.dart';

class BookingHistoryPage extends StatefulWidget {
  const BookingHistoryPage({super.key});

  @override
  State<BookingHistoryPage> createState() => _BookingHistoryPageState();
}

class _BookingHistoryPageState extends State<BookingHistoryPage> {
  final User? _user = FirebaseAuth.instance.currentUser;


  bool _sortDescending = true;
  DateTime? _selectedDate;
  String? _selectedPropertyId;
  String _filterType = 'none'; 
  List<Map<String, String>> _properties = [];

  @override
  void initState() {
    super.initState();
    _fetchFilterData();
  }

  Future<void> _fetchFilterData() async {
    if (_user == null) return;

    final bookingsSnapshot = await FirebaseFirestore.instance
        .collection('bookings')
        .where('seekerId', isEqualTo: _user.uid)
        .get();

    final uniqueProperties = <String, String>{};
    for (var doc in bookingsSnapshot.docs) {
      final data = doc.data();
      final propertyId = data['propertyId'] as String?;
      final propertyName = data['propertyName'] as String?;
      if (propertyId != null && propertyName != null) {
        uniqueProperties[propertyId] = propertyName;
      }
    }

    if (mounted) {
      setState(() {
        _properties = uniqueProperties.entries
            .map((e) => {'id': e.key, 'name': e.value})
            .toList();
      });
    }
  }

  Stream<QuerySnapshot> _buildFilteredStream() {
    if (_user == null) return const Stream.empty();

    Query query = FirebaseFirestore.instance
        .collection('bookings')
        .where('seekerId', isEqualTo: _user.uid)
        .where('status', whereIn: ['checked_out', 'declined', 'cancelled']);

    
    if (_selectedPropertyId != null) {
      query = query.where('propertyId', isEqualTo: _selectedPropertyId);
    }

    
    if (_selectedDate != null) {
      if (_filterType == 'monthly') {
        final startOfMonth = DateTime(_selectedDate!.year, _selectedDate!.month, 1);
        final endOfMonth = DateTime(_selectedDate!.year, _selectedDate!.month + 1, 1);
        query = query
            .where('updatedAt', isGreaterThanOrEqualTo: startOfMonth)
            .where('updatedAt', isLessThan: endOfMonth);
      }
    }

    
    query = query.orderBy('updatedAt', descending: _sortDescending);

    return query.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking History')),
        body: const Center(child: Text('Please log in to view history.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Booking History',
          style: TextStyle(
            color: AppColors.textDark,
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
            icon: const Icon(Iconsax.filter, color: AppColors.textDark),
            onPressed: _showFilterDialog,
            tooltip: 'Filter History',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _buildFilteredStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Iconsax.receipt_search,
                      size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No Past Bookings',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your completed or cancelled bookings will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final booking = doc.data() as Map<String, dynamic>;
              booking['id'] = doc.id; 
              return _buildHistoryCard(context, booking);
            },
          );
        },
      ),
    );
  }

  void _showFilterDialog() {
    
    bool tempSortDescending = _sortDescending;
    String? tempPropertyId = _selectedPropertyId;
    String tempFilterType = _filterType;
    DateTime? tempDate = _selectedDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter & Sort',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const Divider(height: 24),

                  
                  const Text('Sort By',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  DropdownButton<bool>(
                    value: tempSortDescending,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: true, child: Text('Latest to Oldest')),
                      DropdownMenuItem(
                          value: false, child: Text('Oldest to Latest')),
                    ],
                    onChanged: (val) =>
                        setModalState(() => tempSortDescending = val!),
                  ),
                  const SizedBox(height: 16),

                  
                  const Text('Property',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  DropdownButton<String?>(
                    value: tempPropertyId,
                    isExpanded: true,
                    hint: const Text('All Properties'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('All Properties')),
                      ..._properties.map((prop) => DropdownMenuItem<String?>(
                          value: prop['id'], child: Text(prop['name']!))),
                    ],
                    onChanged: (val) =>
                        setModalState(() => tempPropertyId = val),
                  ),
                  const SizedBox(height: 16),

                  
                  const Text('Date',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  DropdownButton<String>(
                    value: tempFilterType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('All Time')),
                      DropdownMenuItem(
                          value: 'monthly', child: Text('Filter by Year & Month')),
                    ],
                    onChanged: (val) {
                      setModalState(() {
                        tempFilterType = val!;
                        if (val == 'none') {
                          tempDate = null;
                        } else {
                          tempDate = DateTime.now(); 
                        }
                      });
                    },
                  ),

                  if (tempFilterType != 'none') ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: tempDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDatePickerMode: DatePickerMode.year,
                        );
                        if (picked != null) {
                          setModalState(() => tempDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Selected Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          tempDate == null
                              ? 'Tap to select'
                              : DateFormat.yMMMM().format(tempDate!),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              tempSortDescending = true;
                              tempPropertyId = null;
                              tempFilterType = 'none';
                              tempDate = null;
                            });
                          },
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _sortDescending = tempSortDescending;
                              _selectedPropertyId = tempPropertyId;
                              _filterType = tempFilterType;
                              _selectedDate = tempDate;
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryCard(
      BuildContext context, Map<String, dynamic> booking) {
    final status = booking['status'] ?? 'unknown';
    final propertyName = booking['propertyName'] ?? 'Property';
    final roomName = booking['roomName'] ?? 'Room';
    final imageUrl = booking['propertyImageUrl'] as String?;
    final bookingId = booking['id'] as String?;

    
    final bookingDate = (booking['createdAt'] as Timestamp?)?.toDate();
    final moveInDate = (booking['bookingDate'] as Timestamp?)?.toDate();
    final finalizedAt = (booking['updatedAt'] as Timestamp?)?.toDate();

    return Card(
      margin: const EdgeInsets.only(bottom: 20.0),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (bookingId != null) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => BookingTransactionHistoryPage(bookingId: bookingId)));
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15.0)),
              child: Stack(
                children: [
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                          height: 150, color: Colors.grey[200]),
                      errorWidget: (context, url, error) => Container(
                          height: 150,
                          color: Colors.grey[300],
                          child: const Icon(Iconsax.house,
                              size: 60, color: Colors.grey)),
                    )
                  else
                    Container(
                      height: 150,
                      color: Colors.grey[300],
                      child:
                          const Icon(Iconsax.house, size: 60, color: Colors.grey),
                    ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: BookingHelpers.getStatusColor(status),
                        borderRadius: BorderRadius.circular(20),
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
                    propertyName,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    roomName,
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                        fontFamily: 'Poppins'),
                  ),
                  const Divider(height: 24),
                  if (bookingDate != null)
                    _buildDateRow(
                      icon: Iconsax.calendar_add,
                      label: 'Booking Date',
                      date: bookingDate,
                    ),
                  if (moveInDate != null)
                    _buildDateRow(
                      icon: Iconsax.login,
                      label: 'Move-in Date',
                      date: moveInDate,
                    ),
                  if (finalizedAt != null)
                    _buildDateRow(
                      icon: Iconsax.calendar_tick,
                      label: _getFinalizedLabel(status),
                      date: finalizedAt,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getFinalizedLabel(String status) {
    switch (status) {
      case 'checked_out':
        return 'Checked Out On';
      case 'cancelled':
        return 'Cancelled On';
      case 'declined':
        return 'Declined On';
      default:
        return 'Date';
    }
  }

  Widget _buildDateRow({
    required IconData icon,
    required String label,
    required DateTime date,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(color: Colors.grey[700], fontFamily: 'Poppins'),
          ),
          Text(
            DateFormat('MMM d, yyyy').format(date),
            style: TextStyle(
                color: Colors.grey[800],
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}