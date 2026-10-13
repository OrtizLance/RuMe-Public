import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rume/components/loading_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rume/components/app_colors.dart';
import 'package:go_router/go_router.dart';
import 'package:rume/owner_module/dashboard/property_summary_card.dart';
import 'package:rume/owner_module/dashboard/week_calendar.dart';
import 'package:rume/owner_module/dashboard/analytics_preview_card.dart';
import 'package:rume/owner_module/dashboard/owner_notifications_page.dart';
import 'package:rume/owner_module/inquiries/o_inquiries.dart'; 
import 'package:iconsax/iconsax.dart'; 

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final User? _user = FirebaseAuth.instance.currentUser;
  List<DocumentSnapshot> _verifiedProperties = [];
  bool _isLoading = true;
  String? _selectedPropertyId;
  int _currentPropertyIndex = 0;

  
  String _userName = '';
  String _userEmail = '';
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadUserProfile() async {
    if (_user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _userName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
              .trim();
          _userEmail = _user.email ?? '';
          _profileImageUrl = data['profileImageUrl'];
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  Future<void> _loadDashboardData() async {
    if (_user == null || !mounted) return;
    setState(() => _isLoading = true);

    final dataFetchFuture = Future.wait([
      _loadUserProfile(),
      _fetchVerifiedProperties(),
    ]);

    final delayFuture = Future.delayed(const Duration(milliseconds: 800));

    await Future.wait([dataFetchFuture, delayFuture]);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchVerifiedProperties() async {
    if (_user == null) return;

    final propertiesSnapshot = await FirebaseFirestore.instance
        .collection('properties')
        .where('ownerId', isEqualTo: _user.uid)
        .where('status', isEqualTo: 'verified')
        .orderBy('createdAt', descending: true)
        .get();

    if (mounted) {
      _verifiedProperties = propertiesSnapshot.docs;
      if (_verifiedProperties.isNotEmpty) {
        _selectedPropertyId = _verifiedProperties[0].id;
        _currentPropertyIndex = 0;
      }
    }
  }

  void _showPropertySwitcher() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600, maxWidth: 500),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.swap_horiz,
                    color: AppColors.blue900,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Switch Property',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.blue900,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _verifiedProperties.length,
                  itemBuilder: (context, index) {
                    final property = _verifiedProperties[index];
                    final propertyData =
                        property.data() as Map<String, dynamic>;
                    final propertyName =
                        propertyData['name'] ?? 'Unnamed Property';
                    final isSelected = index == _currentPropertyIndex;

                    return Card(
                      elevation: isSelected ? 4 : 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.blue900
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            _currentPropertyIndex = index;
                            _selectedPropertyId = property.id;
                          });
                          Navigator.pop(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.blue900.withOpacity(0.1)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.home_work,
                                  color: isSelected
                                      ? AppColors.blue900
                                      : Colors.grey[600],
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      propertyName,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? AppColors.blue900
                                            : Colors.black87,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      propertyData['address'] ?? 'No address',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.blue900,
                                  size: 28,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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

    if (_isLoading) {
      return const StandardLoadingScreen();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.blue900.withOpacity(0.1),
              backgroundImage: _profileImageUrl != null
                  ? CachedNetworkImageProvider(_profileImageUrl!)
                  : null,
              child: _profileImageUrl == null
                  ? const Icon(Icons.person, color: Colors.black, size: 24)
                  : null,
            ),
            const SizedBox(width: 12),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _userName.isEmpty ? 'Owner' : _userName,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _userEmail,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chats')
                .where('ownerId', isEqualTo: _user.uid)
                .where('unreadByOwner', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              final hasUnread =
                  snapshot.hasData && snapshot.data!.docs.isNotEmpty;
              final unreadCount = snapshot.data?.docs.length ?? 0;

              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(
                      Iconsax.message_search,
                      color: Colors.black45,
                      size: 30,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OwnerInquiriesPage(),
                        ),
                      );
                    },
                  ),
                  if (hasUnread)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(_user.uid)
                .collection('notifications')
                .where('read', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final hasUnread =
                  snapshot.hasData && snapshot.data!.docs.isNotEmpty;
              final unreadCount = snapshot.data?.docs.length ?? 0;

              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(
                      Iconsax.notification,
                      color: Colors.black45,
                      size: 30,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OwnerNotificationsPage(),
                        ),
                      );
                    },
                  ),
                  if (hasUnread)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _verifiedProperties.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),

                    
                    if (_verifiedProperties.length > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: const RadialGradient(
                              center: Alignment.centerLeft,
                              radius: 2.0,
                              colors: [
                                Color(0xFF4FC3F7),
                                Color.fromARGB(255, 40, 127, 226),
                                Color.fromARGB(255, 24, 89, 186),
                              ],
                              stops: [0.0, 0.5, 1.0],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1565C0).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _showPropertySwitcher,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 16,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.swap_horiz,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Switch Property',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(width: 15),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        '${_verifiedProperties.length}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (_verifiedProperties.length > 1)
                      const SizedBox(height: 10),

                    
                    if (_selectedPropertyId != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: PropertySummaryCard(
                          key: ValueKey(_selectedPropertyId!),
                          propertyDoc:
                              _verifiedProperties[_currentPropertyIndex],
                          ownerId: _user.uid,
                        ),
                      ),

                    const SizedBox(height: 16),

                    
                    if (_selectedPropertyId != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: WeekCalendarWidget(
                          key: ValueKey(_selectedPropertyId!),
                          propertyId: _selectedPropertyId!,
                          ownerId: _user.uid,
                        ),
                      ),

                    const SizedBox(height: 16),

                    
                    if (_selectedPropertyId != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: AnalyticsPreviewCard(
                          key: ValueKey(_selectedPropertyId!),
                          propertyId: _selectedPropertyId!,
                          ownerId: _user.uid,
                          onViewFullAnalytics: () {
                            context.go('/owner-analytics');
                          },
                        ),
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_work_outlined, size: 100, color: Colors.grey[400]),
            const SizedBox(height: 24),
            const Text(
              'No Verified Properties Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Add and verify your first property to get started with your dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}