
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rume/owner_module/bookings/occupied_rooms_list.dart';
import 'package:rume/owner_module/bookings/room_br_list.dart';
import 'package:rume/owner_module/room_listings/property_verification_page.dart';
import 'package:rume/components/loading_screen.dart';
import 'package:rume/owner_module/room_listings/room_listings.dart';
import 'package:intl/intl.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class OwnerListings extends StatefulWidget {
  const OwnerListings({super.key});

  @override
  State<OwnerListings> createState() => _OwnerListingsState();
}

class _OwnerListingsState extends State<OwnerListings> {
  final User? _user = FirebaseAuth.instance.currentUser;
  final Set<String> _selectedProperties = {};
  bool _isSelectionMode = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDataWithDelay();
  }

  Future<void> _loadDataWithDelay() async {
    
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSelectedProperties() async {
    if (_selectedProperties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          content: AwesomeSnackbarContent(
            title: 'No Selection',
            message: 'Please select at least one property to delete.',
            contentType: ContentType.warning,
          ),
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
            Text('Confirm Deletion', style: TextStyle(fontSize: 22)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedProperties.length} '
          'selected ${_selectedProperties.length == 1 ? 'property' : 'properties'}?\n\n'
          'This will permanently delete the property, all its rooms, and all associated images. '
          'This action cannot be undone.',
          textAlign: TextAlign.justify,
          style: const TextStyle(fontSize: 15),
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

    BuildContext loadingDialogContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        loadingDialogContext = ctx;
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );

    int deletedImages = 0;
    int failedImages = 0;

    try {
      for (final propertyId in _selectedProperties) {
        final propertyDoc = await FirebaseFirestore.instance
            .collection('properties')
            .doc(propertyId)
            .get();

        if (!propertyDoc.exists) continue;

        final propertyData = propertyDoc.data()!;
        final ownerId = propertyData['ownerId'];

        
        final roomsSnapshot = await FirebaseFirestore.instance
            .collection('properties')
            .doc(propertyId)
            .collection('rooms')
            .get();

        for (final roomDoc in roomsSnapshot.docs) {
          final roomData = roomDoc.data();
          final images = List<String>.from(roomData['images'] ?? []);

          for (final imageUrl in images) {
            if (imageUrl.isEmpty) continue;

            try {
              final ref = FirebaseStorage.instance.refFromURL(imageUrl);
              await ref.delete();
              deletedImages++;
              debugPrint('Deleted room image: ${ref.fullPath}');
            } catch (e) {
              failedImages++;
              debugPrint('Failed to delete room image: $imageUrl - Error: $e');
            }
          }

          await roomDoc.reference.delete();
        }

        
        final verificationData =
            propertyData['verificationData'] as Map<String, dynamic>?;

        if (verificationData != null) {
          final verificationFiles = {
            'propertyFrontUrl': 'property_front.jpg',
            'businessPermitUrl': 'business_permit.jpg',
            'validIdFrontUrl': 'valid_id_front.jpg',
            'validIdBackUrl': 'valid_id_back.jpg',
          };

          
          for (final entry in verificationFiles.entries) {
            final url = verificationData[entry.key];
            if (url == null || url.toString().isEmpty) continue;

            bool deleted = false;

            try {
              
              await FirebaseStorage.instance.refFromURL(url).delete();
              deletedImages++;
              deleted = true;
              debugPrint('✓ Deleted ${entry.key} via URL');
            } catch (urlError) {
              debugPrint('URL deletion failed for ${entry.key}: $urlError');

              
              try {
                final path =
                    'property_verification/$ownerId/$propertyId/${entry.value}';
                await FirebaseStorage.instance.ref(path).delete();
                deletedImages++;
                deleted = true;
                debugPrint('✓ Deleted ${entry.key} via path: $path');
              } catch (pathError) {
                debugPrint('⨯ Both deletion methods failed for ${entry.key}');
                debugPrint('  URL error: $urlError');
                debugPrint('  Path error: $pathError');
              }
            }

            if (!deleted) {
              failedImages++;
            }
          }

          
          final faceScanUrls = List<String>.from(
            verificationData['faceScanUrls'] ?? [],
          );
          for (int i = 0; i < faceScanUrls.length; i++) {
            final url = faceScanUrls[i];
            if (url.isEmpty) continue;

            bool deleted = false;

            try {
              await FirebaseStorage.instance.refFromURL(url).delete();
              deletedImages++;
              deleted = true;
              debugPrint('✓ Deleted face scan $i via URL');
            } catch (urlError) {
              debugPrint('URL deletion failed for face scan $i: $urlError');

              try {
                final path =
                    'property_verification/$ownerId/$propertyId/face_$i.jpg';
                await FirebaseStorage.instance.ref(path).delete();
                deletedImages++;
                deleted = true;
                debugPrint('✓ Deleted face scan $i via path');
              } catch (pathError) {
                debugPrint('⨯ Both methods failed for face scan $i');
                debugPrint('  URL error: $urlError');
                debugPrint('  Path error: $pathError');
              }
            }

            if (!deleted) {
              failedImages++;
            }
          }
        }

        
        await FirebaseFirestore.instance
            .collection('properties')
            .doc(propertyId)
            .delete();

        debugPrint(
          'Property $propertyId deleted. Images: $deletedImages deleted, $failedImages failed',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.transparent,
            content: AwesomeSnackbarContent(
              title: 'Success!',
              message:
                  '${_selectedProperties.length} ${_selectedProperties.length == 1 ? 'property' : 'properties'} deleted successfully',
              contentType: ContentType.success,
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() {
          _selectedProperties.clear();
          _isSelectionMode = false;
        });
      }
    } catch (e) {
      debugPrint('Error during property deletion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.transparent,
            content: AwesomeSnackbarContent(
              title: 'Deletion Failed',
              message: 'An error occurred while deleting properties: $e',
              contentType: ContentType.failure,
            ),
          ),
        );
      }
    } finally {
      if (mounted && Navigator.of(loadingDialogContext).canPop()) {
        Navigator.pop(loadingDialogContext);
      }
    }
  }

  Future<Map<String, Map<String, int>>> _getAllCounts(
    List<QueryDocumentSnapshot> properties,
  ) async {
    final Map<String, Map<String, int>> allCounts = {};
    final ownerId = _user?.uid;
    if (ownerId == null) return {};

    
    await Future.wait(
      properties.map((property) async {
        final propertyId = property.id;

        
        final bookingsFuture = FirebaseFirestore.instance
            .collection('bookings')
            .where('ownerId', isEqualTo: ownerId)
            .where('propertyId', isEqualTo: propertyId)
            .where('status', whereIn: ['pending', 'awaiting_payment'])
            .count() 
            .get();

        
        final occupiedOnlineFuture = FirebaseFirestore.instance
            .collection('bookings')
            .where('ownerId', isEqualTo: ownerId)
            .where('propertyId', isEqualTo: propertyId)
            .where('status', isEqualTo: 'booked')
            .count()
            .get();

        
        final occupiedManualFuture = FirebaseFirestore.instance
            .collection('manualOccupancies')
            .where('ownerId', isEqualTo: ownerId)
            .where('propertyId', isEqualTo: propertyId)
            .where('status', isEqualTo: 'occupied')
            .count()
            .get();

        
        final results = await Future.wait([
          bookingsFuture,
          occupiedOnlineFuture,
          occupiedManualFuture,
        ]);

        
        allCounts[propertyId] = {
          'bookings': results[0].count ?? 0,
          'occupied': (results[1].count ?? 0) + (results[2].count ?? 0),
        };
      }),
    );

    return allCounts;
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedProperties.clear();
      }
    });
  }

  void _togglePropertySelection(String propertyId) {
    setState(() {
      if (_selectedProperties.contains(propertyId)) {
        _selectedProperties.remove(propertyId);
      } else {
        _selectedProperties.add(propertyId);
      }
    });
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case 'verified':
        bgColor = Colors.green;
        textColor = Colors.white;
        icon = Icons.verified;
        break;
      case 'pending':
        bgColor = Colors.orange;
        textColor = Colors.white;
        icon = Icons.hourglass_empty;
        break;
      case 'declined':
        bgColor = Colors.red;
        textColor = Colors.white;
        icon = Icons.cancel;
        break;
      default:
        bgColor = Colors.red;
        textColor = Colors.white;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          Icon(icon, color: textColor, size: 16),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _formatVerificationSchedule(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String _formatDateVerified(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    return DateFormat('MMM dd, yyyy').format(date);
  }

  Widget _buildOverlayStat(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingStars(double rating, int reviewCount) {
    List<Widget> stars = [];
    int fullStars = rating.floor();
    bool hasHalfStar = (rating - fullStars) >= 0.5;

    
    for (int i = 0; i < fullStars; i++) {
      stars.add(const Icon(Icons.star, color: Colors.amber, size: 18));
    }

    
    if (hasHalfStar) {
      stars.add(const Icon(Icons.star_half, color: Colors.amber, size: 18));
    }

    
    int emptyStars = 5 - stars.length;
    for (int i = 0; i < emptyStars; i++) {
      stars.add(const Icon(Icons.star_border, color: Colors.amber, size: 18));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...stars,
          const SizedBox(width: 6),
          Text(
            '${rating.toStringAsFixed(1)} ($reviewCount)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in as owner')),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('properties')
          .where('ownerId', isEqualTo: _user.uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        
        if (_isLoading ||
            (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData)) {
          return const StandardLoadingScreen();
        }

        final properties = snapshot.data?.docs ?? [];

        if (properties.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.home_work_outlined,
                  size: 120,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'No properties yet',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your first property to get started',
                  style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            centerTitle: true,
            title: Text(
              "Listings",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              if (_isSelectionMode)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black),
                  onPressed: _toggleSelectionMode,
                )
              else
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.black54),
                  onPressed: _toggleSelectionMode,
                  tooltip: 'Select properties to delete',
                ),
            ],
          ),
          body: FutureBuilder<Map<String, Map<String, int>>>(
            future: _getAllCounts(properties),
            builder: (context, countSnapshot) {
              if (countSnapshot.connectionState == ConnectionState.waiting &&
                  !countSnapshot.hasData) {
                
                return const Center(child: CircularProgressIndicator());
              }

              if (countSnapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      const Text('Error loading counts'),
                      Text(
                        '${countSnapshot.error}',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              final allCounts = countSnapshot.data ?? {};

              return Stack(
                children: [
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: properties.length,
                    itemBuilder: (context, index) {
                      final property = properties[index];
                      final data = property.data() as Map<String, dynamic>;
                      final propertyId = property.id;
                      final propertyName = data['name'] ?? 'Unnamed Property';
                      final status = data['status'] ?? 'pending';

                      final counts =
                          allCounts[propertyId] ??
                          {'bookings': 0, 'occupied': 0};
                      final bookingCount = counts['bookings']!;
                      final occupiedCount = counts['occupied']!;

                      
                      final viewedBy =
                          data['viewedBy'] as Map<String, dynamic>? ?? {};
                      final totalViews = viewedBy.length;
                      final averageRating =
                          (data['averageRating'] as num?)?.toDouble() ?? 0.0;
                      final ratingCount = data['ratingCount'] as int? ?? 0;

                      
                      final verificationData =
                          data['verificationData'] as Map<String, dynamic>?;
                      final propertyFrontUrl =
                          verificationData?['propertyFrontUrl'] as String?;

                      
                      final verificationSchedule =
                          data['verificationSchedule'] as Timestamp?;

                      
                      final dateVerified = data['dateVerified'] as Timestamp?;

                      final isSelected = _selectedProperties.contains(
                        propertyId,
                      );

                      return GestureDetector(
                        onTap: () {
                          if (_isSelectionMode) {
                            _togglePropertySelection(propertyId);
                          } else if (status == 'verified' ||
                              status == 'pending') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RoomListingsPage(
                                  propertyId: propertyId,
                                  propertyName: propertyName,
                                ),
                              ),
                            );
                          } else if (status == 'declined') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.cancel,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Property verification was declined. You cannot add rooms.',
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            _toggleSelectionMode();
                          }
                          _togglePropertySelection(propertyId);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: isSelected
                                ? Border.all(color: Colors.deepOrange, width: 3)
                                : null,
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Column(
                                  children: [
                                    
                                    Container(
                                      height: 160,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                      ),
                                      child: Stack(
                                        children: [
                                          if (propertyFrontUrl != null &&
                                              propertyFrontUrl.isNotEmpty)
                                            CachedNetworkImage(
                                              imageUrl: propertyFrontUrl,
                                              width: double.infinity,
                                              height: 160,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  Container(
                                                    color: Colors.grey[200],
                                                    child: const Center(
                                                      child:
                                                          CircularProgressIndicator(),
                                                    ),
                                                  ),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const Center(
                                                        child: Icon(
                                                          Icons.home_work,
                                                          size: 60,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                            )
                                          else
                                            const Center(
                                              child: Icon(
                                                Icons.home_work,
                                                size: 60,
                                                color: Colors.white,
                                              ),
                                            ),
                                          if (status != 'verified')
                                            Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black.withOpacity(
                                                      0.3,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          Positioned(
                                            top: 12,
                                            left: 12,
                                            right: 12,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (ratingCount > 0)
                                                  _buildRatingStars(
                                                    averageRating,
                                                    ratingCount,
                                                  )
                                                else
                                                  _buildOverlayStat(
                                                    Icons.star_border,
                                                    'No reviews',
                                                  ),
                                                const SizedBox(height: 8),
                                                _buildOverlayStat(
                                                  Icons.visibility_outlined,
                                                  '$totalViews ${totalViews == 1 ? 'view' : 'views'}',
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.only(
                                          bottomLeft: Radius.circular(16),
                                          bottomRight: Radius.circular(16),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          
                                          Text(
                                            propertyName,
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 12),
                                          
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.location_on,
                                                size: 18,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (data['barangay'] !=
                                                        null)
                                                      Text(
                                                        data['barangay'],
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color:
                                                              Colors.grey[700],
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                    if (data['city'] != null)
                                                      Text(
                                                        data['city'],
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color:
                                                              Colors.grey[700],
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                    if (data['province'] !=
                                                        null)
                                                      Text(
                                                        data['province'],
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color:
                                                              Colors.grey[700],
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                    if (data['region'] != null)
                                                      Text(
                                                        data['region'],
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color:
                                                              Colors.grey[700],
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          
                                          if (status == 'verified' &&
                                              dateVerified != null) ...[
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.check_circle,
                                                  size: 16,
                                                  color: Colors.green.shade700,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Date Verified: ${_formatDateVerified(dateVerified)}',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color:
                                                        Colors.green.shade700,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          
                                          if (verificationSchedule != null &&
                                              status == 'pending') ...[
                                            const SizedBox(height: 12),
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.blue[50],
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.blue[200]!,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.schedule,
                                                    size: 18,
                                                    color: Colors.blue[700],
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Verification Schedule:',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .blue[700],
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          _formatVerificationSchedule(
                                                            verificationSchedule,
                                                          ),
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: Colors
                                                                .blue[900],
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          const Divider(height: 24),
                                          
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildSquareButton(
                                                  icon: Icons.pending_actions,
                                                  label: 'Requests',
                                                  count: bookingCount,
                                                  color: Colors.orange,
                                                  onTap: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          RoomBookingRequestsList(
                                                            propertyId:
                                                                propertyId,
                                                            propertyName:
                                                                data['name'] ??
                                                                'Property',
                                                            ownerId: _user.uid,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: _buildSquareButton(
                                                  icon: Icons.meeting_room,
                                                  label: 'Occupied',
                                                  count: occupiedCount,
                                                  color: Colors.green,
                                                  onTap: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          OccupiedRoomsListPage(
                                                            propertyId:
                                                                propertyId,
                                                            propertyName:
                                                                data['name'] ??
                                                                'Property',
                                                            ownerId: _user.uid,
                                                          ),
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
                              ),
                              
                              Positioned(
                                top: 12,
                                right: 12,
                                child: _buildStatusBadge(status),
                              ),
                              
                              if (_isSelectionMode)
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.blueAccent
                                          : Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.blueAccent
                                            : Colors.grey[400]!,
                                        width: 2,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.check,
                                      size: 20,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.transparent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  
                  if (_isSelectionMode && _selectedProperties.isNotEmpty)
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: FloatingActionButton.extended(
                        onPressed: _deleteSelectedProperties,
                        backgroundColor: Colors.red,
                        icon: const Icon(Icons.delete, color: Colors.white),
                        label: Text(
                          'Delete (${_selectedProperties.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          floatingActionButton: !_isSelectionMode
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PropertyVerificationPage(),
                      ),
                    );
                    if (result == true) {
                      setState(() {});
                    }
                  },
                  label: const Text(
                    'Create Property',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  icon: const Icon(Icons.add, color: Colors.white),
                  backgroundColor: Colors.blueAccent,
                )
              : null,
        );
      },
    );
  }

  Widget _buildSquareButton({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return AspectRatio(
      aspectRatio: 1.5,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(1),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 40),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            if (count > 0)
              Positioned(
                top: 6,
                right: 6,
                child: CircleAvatar(
                  radius: 14, 
                  backgroundColor: Colors.red, 
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Text(
                      count > 9 ? '9+' : count.toString(),
                      style: const TextStyle(
                        color: Colors.white, 
                        fontWeight: FontWeight.bold,
                        fontSize: 14, 
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
