
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shimmer/shimmer.dart';

class SeekerRoomDetailsPage extends StatelessWidget {
  final String roomId;
  final Map<String, dynamic> data;

  const SeekerRoomDetailsPage({
    super.key,
    required this.roomId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final images = List<String>.from(data['images'] ?? []);
    final amenities = List<String>.from(data['amenities'] ?? []);
    final price = data['price']?.toString() ?? '0';
    final capacity = data['capacity']?.toString() ?? '1';
    final description = data['description'] ?? '';
    final status = data['status'] ?? 'available';
    final roomName = data['name'] ?? 'Room';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.arrow_back, color: Colors.black87),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: images.isNotEmpty
                  ? _ModernImageCarousel(
                      urls: images,
                    ).animate().fadeIn(duration: 400.ms)
                  : Container(
                      color: Colors.grey[100],
                      child: Center(
                        child: Icon(
                          Iconsax.house,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                      ),
                    ),
            ),
          ),

          
          SliverToBoxAdapter(
            child: Container(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                roomName,
                                style: GoogleFonts.poppins(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            _StatusBadge(status: status),
                          ],
                        ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),
                        const SizedBox(height: 20),

                        
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.shade50,
                                Colors.green.shade100.withOpacity(0.3),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.green.shade200,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Iconsax.wallet_3,
                                  color: Colors.green.shade700,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Monthly Rent',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '₱$price',
                                          style: GoogleFonts.roboto(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                            height: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: Text(
                                            '/month',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Colors.green.shade600,
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
                        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2),

                        const SizedBox(height: 16),

                        
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Iconsax.people,
                                  color: Colors.blue.shade700,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Maximum capacity: ',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Text(
                                '$capacity ${capacity == '1' ? 'pax' : 'pax'}',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),
                      ],
                    ),
                  ),

                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Divider(height: 1, color: Colors.grey[200]),
                  ),

                  
                  if (description.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Iconsax.document_text,
                                color: Colors.grey[700],
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Description',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            description,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              height: 1.7,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Divider(height: 1, color: Colors.grey[200]),
                    ),
                  ],

                  
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Iconsax.star,
                              color: Colors.grey[700],
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Amenities',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (amenities.isNotEmpty)
                          _AmenitiesGrid(
                            amenities: amenities,
                          ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1)
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Iconsax.info_circle,
                                  color: Colors.grey[400],
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'No amenities listed',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Divider(height: 1, color: Colors.grey[200]),
                  ),

                  
                  _FeedbackSection(
                    roomId: roomId,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _ModernImageCarousel extends StatefulWidget {
  final List<String> urls;

  const _ModernImageCarousel({required this.urls});

  @override
  State<_ModernImageCarousel> createState() => _ModernImageCarouselState();
}

class _ModernImageCarouselState extends State<_ModernImageCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return Container(
        color: Colors.grey[100],
        child: Center(
          child: Icon(Iconsax.house, size: 80, color: Colors.grey[300]),
        ),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentPage = index),
          itemCount: widget.urls.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _FullScreenGallery(
                      imageUrls: widget.urls,
                      initialIndex: index,
                    ),
                  ),
                );
              },
              child: Hero(
                tag: widget.urls[index],
                child: CachedNetworkImage(
                  imageUrl: widget.urls[index],
                  fit: BoxFit.cover,  
                  width: double.infinity,
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[100],
                    child: Center(
                      child: Icon(
                        Iconsax.gallery_slash,
                        size: 50,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        
        if (widget.urls.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.urls.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),

        
        if (widget.urls.length > 1)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Iconsax.gallery, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    '${_currentPage + 1}/${widget.urls.length}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}


class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final bool isAvailable = status == 'available';
    final color = isAvailable ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.toUpperCase(),
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}


class _AmenitiesGrid extends StatelessWidget {
  final List<String> amenities;

  const _AmenitiesGrid({required this.amenities});

  IconData _getAmenityIcon(String amenity) {
    return Iconsax.tick_circle;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: amenities.take(12).map((amenity) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getAmenityIcon(amenity),
                size: 16,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                amenity,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}


class _FeedbackSection extends StatelessWidget {
  final String roomId;
  const _FeedbackSection({required this.roomId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Iconsax.message_text,
                color: Colors.grey[700],
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Reviews & Feedback',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('feedbacks')
                .where('roomId', isEqualTo: roomId)
                .where('hidden', isNotEqualTo: true)
                .where('status', isEqualTo: 'approved')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Iconsax.message_remove,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'No reviews for this room yet',
                        style: GoogleFonts.poppins(
                          color: Colors.grey[500],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final feedbackDocs = snapshot.data!.docs;

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: feedbackDocs.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final feedbackData =
                      feedbackDocs[index].data() as Map<String, dynamic>;
                  return _FeedbackCard(feedbackData: feedbackData)
                      .animate()
                      .fadeIn(delay: (100 * index).ms)
                      .slideY(begin: 0.2);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}


class _FeedbackCard extends StatelessWidget {
  final Map<String, dynamic> feedbackData;

  const _FeedbackCard({required this.feedbackData});

  String _obfuscateName(String firstName, String lastName) {
    if (firstName.isEmpty) return 'A...';
    final firstInitial = firstName[0];
    final lastInitial = lastName.isNotEmpty ? lastName[0] : '';
    return '$firstInitial*** $lastInitial***';
  }

  Widget _buildRatingStars(double rating) {
    List<Widget> stars = [];
    int fullStars = rating.floor();
    for (int i = 0; i < 5; i++) {
      stars.add(Icon(
        i < fullStars ? Iconsax.star1 : Iconsax.star,
        color: Colors.amber.shade600,
        size: 16,
      ));
    }
    return Row(children: stars);
  }

  @override
  Widget build(BuildContext context) {
    final seekerId = feedbackData['seekerId'] as String?;
    final rating = (feedbackData['rating'] as num?)?.toDouble() ?? 0.0;
    final description = feedbackData['description'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<DocumentSnapshot>(
            future: seekerId != null
                ? FirebaseFirestore.instance.collection('users').doc(seekerId).get()
                : null,
            builder: (context, userSnapshot) {
              String name = 'Anonymous';
              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                final firstName = userData['firstName'] as String? ?? '';
                final lastName = userData['lastName'] as String? ?? '';
                name = _obfuscateName(firstName, lastName);
              }
              return Text(
                name,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          _buildRatingStars(rating),
          const SizedBox(height: 12),
          Text(
            description,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}


class _FullScreenGallery extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _FullScreenGallery({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} of ${widget.imageUrls.length}',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
      ),
      body: PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: widget.imageUrls.length,
        builder: (context, index) {
          final imageUrl = widget.imageUrls[index];
          return PhotoViewGalleryPageOptions(
            imageProvider: CachedNetworkImageProvider(imageUrl),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            heroAttributes: PhotoViewHeroAttributes(tag: imageUrl),
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey[900],
              child: Center(
                child: Icon(
                  Iconsax.gallery_slash,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
          );
        },
        scrollPhysics: const BouncingScrollPhysics(),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (context, event) => Container(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
              value: event == null
                  ? null
                  : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
            ),
          ),
        ),
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}