
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/owner_module/room_listings/room_details_page.dart';
import 'package:rume/owner_module/room_listings/room_form_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class RoomListingsPage extends StatefulWidget {
  final String propertyId;
  final String propertyName;

  const RoomListingsPage({
    super.key,
    required this.propertyId,
    required this.propertyName,
  });

  @override
  State<RoomListingsPage> createState() => _RoomListingsPageState();
}

class _RoomListingsPageState extends State<RoomListingsPage> {
  final User? _user = FirebaseAuth.instance.currentUser;

  
  
  Future<Map<String, dynamic>> _getVerificationData() async {
    if (_user == null) {
      debugPrint('❌ User is null');
      return {'schedule': null, 'rooms': []};
    }

    try {
      debugPrint(
        '🔍 Fetching all rooms for verification for property: ${widget.propertyId}',
      );

      final snapshot = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .where('verificationStatus', whereIn: ['pending', 'reverify'])
          .get();

      debugPrint(
        '📊 Found ${snapshot.docs.length} rooms needing verification.',
      );

      if (snapshot.docs.isEmpty) {
        return {'schedule': null, 'rooms': []};
      }

      List<Map<String, dynamic>> rooms = [];
      Timestamp? earliestSchedule;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final schedule = data['verificationSchedule'] as Timestamp?;

        
        if (schedule != null) {
          if (earliestSchedule == null ||
              schedule.compareTo(earliestSchedule) < 0) {
            earliestSchedule = schedule;
          }
        }

        rooms.add({
          'roomName': data['name'] ?? 'Unknown Room',
          'status': data['verificationStatus'],
        });
      }

      
      rooms.sort(
        (a, b) => (a['roomName'] as String).compareTo(b['roomName'] as String),
      );

      debugPrint(
        '✅ Returning schedule: $earliestSchedule, rooms: ${rooms.length}',
      );
      return {'schedule': earliestSchedule, 'rooms': rooms};
    } catch (e) {
      debugPrint('❌ Error getting verification data: $e');
      return {'schedule': null, 'rooms': []};
    }
  }

  Future<void> _deleteRoom(
    String roomId,
    List<String> imageUrls,
    String roomStatus,
  ) async {
    
    if (roomStatus == 'occupied') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot delete an occupied room. Please check out the occupants first.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Room'),
          ],
        ),
        content: const Text(
          'This will permanently delete the room and all its images. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      
      for (final url in imageUrls) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (e) {
          debugPrint('Failed deleting image: $e');
        }
      }

      
      await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .doc(roomId)
          .delete();

      
      final verifyRequestId = '${widget.propertyId}_$roomId';
      await FirebaseFirestore.instance
          .collection('roomVerifyRequests')
          .doc(verifyRequestId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Room deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete room: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildRoomStatusBadge(String status) {
    Color bgColor;
    IconData icon;

    switch (status) {
      case 'available':
        bgColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'on_hold':
        bgColor = Colors.orange;
        icon = Icons.pause_circle;
        break;
      case 'occupied':
      default:
        bgColor = Colors.red;
        icon = Icons.block;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            status == 'on_hold' ? 'ON HOLD' : status.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  
  
  Widget _buildPendingVerificationBanner() {
    debugPrint('🎨 Building unified verification banner');

    return FutureBuilder<Map<String, dynamic>>(
      future: _getVerificationData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint('⏳ Waiting for verification data...');
          return const SizedBox.shrink(); 
        }

        if (!snapshot.hasData || (snapshot.data!['rooms'] as List).isEmpty) {
          debugPrint('❌ No verification data or no rooms to verify');
          return const SizedBox.shrink();
        }

        final verificationData = snapshot.data!;
        final earliestSchedule = verificationData['schedule'] as Timestamp?;
        final rooms = verificationData['rooms'] as List<Map<String, dynamic>>;

        
        
        if (earliestSchedule != null) {
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.event_available,
                      color: Colors.blue[900],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Room Verification Scheduled',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: Colors.blue[900],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat(
                          'MMMM d, yyyy',
                        ).format(earliestSchedule.toDate()),
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                Text(
                  rooms.length == 1
                      ? 'Room to be verified:'
                      : 'Rooms to be verified:',
                  style: TextStyle(
                    color: Colors.blue[800],
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ...rooms.map((room) {
                  final roomName = room['roomName'] as String;
                  final status = room['status'] as String;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            roomName,
                            style: TextStyle(
                              color: Colors.blue[900],
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          status == 'reverify'
                              ? '(Re-verification)'
                              : '(Verification)',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        }
        
        else {
          final pendingRooms = rooms
              .where((r) => r['status'] == 'pending')
              .toList();

          if (pendingRooms.isEmpty) {
            return const SizedBox.shrink();
          }

          return Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.pending_actions,
                      color: Colors.orange[900],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pendingRooms.length == 1
                            ? '1 Room Pending Verification'
                            : '${pendingRooms.length} Rooms Pending Verification',
                        style: TextStyle(
                          color: Colors.orange[900],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'An admin will schedule a verification date soon.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ...pendingRooms.map((room) {
                  final roomName = room['roomName'] as String;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            roomName,
                            style: TextStyle(
                              color: Colors.orange[900],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Schedule Pending',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in as owner')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Room Listings',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontSize: 20,
              ),
            ),
            Text(
              widget.propertyName,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          
          SliverToBoxAdapter(child: _buildPendingVerificationBanner()),

          
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('properties')
                .doc(widget.propertyId)
                .collection('rooms')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                      ],
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final rooms = snapshot.data?.docs ?? [];

              if (rooms.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.bed_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'No rooms yet',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start by adding your first room',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final roomDoc = rooms[index];
                    final data = roomDoc.data() as Map<String, dynamic>;
                    final images = List<String>.from(data['images'] ?? []);
                    final price = data['price']?.toString() ?? '0';
                    final roomStatus = data['status'] ?? 'available';
                    final roomName = data['name'] ?? 'Untitled Room';
                    final capacity = data['capacity']?.toString() ?? '1';
                    final verificationStatus =
                        data['verificationStatus'] ?? 'pending';

                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.1),
                      child: InkWell(
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RoomDetailsPage(
                                propertyId: widget.propertyId,
                                roomId: roomDoc.id,
                                data: data,
                              ),
                            ),
                          );
                          if (result == true) setState(() {});
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 180,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    bottomLeft: Radius.circular(16),
                                  ),
                                  child: Stack(
                                    children: [
                                      _ImageCarousel(urls: images),
                                      Positioned(
                                        top: 8,
                                        left: 8,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color:
                                                verificationStatus == 'verified'
                                                ? Colors.green
                                                : Colors.orange,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.3,
                                                ),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            verificationStatus == 'verified'
                                                ? Icons.verified
                                                : Icons.unpublished,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topRight: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            roomName,
                                            style: const TextStyle(
                                              fontSize: 23,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Text(
                                                '₱$price',
                                                style: const TextStyle(
                                                  fontFamily: 'Roboto',
                                                  fontSize: 20,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                '/month',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.people,
                                                size: 18,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '$capacity ${capacity == '1' ? 'person' : 'pax'}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              _buildRoomStatusBadge(roomStatus),
                                              const Spacer(),
                                              PopupMenuButton<String>(
                                                onSelected: (value) async {
                                                  if (value == 'delete') {
                                                    await _deleteRoom(
                                                      roomDoc.id,
                                                      images,
                                                      roomStatus,
                                                    );
                                                  }
                                                },
                                                icon: Container(
                                                  padding: const EdgeInsets.all(
                                                    7,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[100],
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.more_vert,
                                                    size: 20,
                                                    color: Colors.blueGrey,
                                                  ),
                                                ),
                                                itemBuilder: (_) {
                                                  List<PopupMenuEntry<String>>
                                                  menuItems = [];
                                                  menuItems.add(
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.delete,
                                                            size: 18,
                                                            color: Colors.red,
                                                          ),
                                                          SizedBox(width: 8),
                                                          Text(
                                                            'Delete',
                                                            style: TextStyle(
                                                              color: Colors.red,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                  return menuItems;
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }, childCount: rooms.length),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RoomFormPage(propertyId: widget.propertyId),
            ),
          );
          if (result == true) setState(() {});
        },
        label: const Text(
          'Create Room',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: AppColors.successGreen,
      ),
    );
  }
}


class _ImageCarousel extends StatefulWidget {
  final List<String> urls;
  const _ImageCarousel({required this.urls});

  @override
  State<_ImageCarousel> createState() => __ImageCarouselState();
}

class __ImageCarouselState extends State<_ImageCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;

    if (urls.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.grey[300]!, Colors.grey[200]!],
          ),
        ),
        child: const Center(
          child: Icon(Icons.bed, size: 50, color: Colors.grey),
        ),
      );
    }

    return Stack(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: urls.length,
            itemBuilder: (context, index) {
              return CachedNetworkImage(
                imageUrl: urls[index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: 180,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.blueAccent,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      color: Colors.grey,
                      size: 40,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (urls.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(urls.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == index ? 16 : 8,
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
        if (urls.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentPage + 1}/${urls.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}