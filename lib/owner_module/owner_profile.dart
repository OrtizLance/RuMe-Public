import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:rume/components/app_colors.dart';
import 'package:iconsax/iconsax.dart';
import 'package:rume/components/loading_screen.dart';
import 'package:google_fonts/google_fonts.dart';
  
class OwnerProfile extends StatefulWidget {
  const OwnerProfile({super.key});

  @override
  State<OwnerProfile> createState() => _OwnerProfileState();
}

class _OwnerProfileState extends State<OwnerProfile> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    setState(() => _isLoading = true);
    final dataFetchFuture = () async {
      if (currentUser == null) return;
      try {
        final docSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .get();
        if (mounted && docSnapshot.exists) {
          _userData = docSnapshot.data();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to fetch user data: $e')),
          );
        }
      }
    }();

    await Future.wait([dataFetchFuture, Future.delayed(const Duration(milliseconds: 800))]);
    if (mounted) setState(() => _isLoading = false);
  }

  void _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error logging out: $e')));
      }
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Not set';
    return DateFormat('MMMM d, yyyy').format(timestamp.toDate());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const StandardLoadingScreen();
    }

    if (currentUser == null) {
      return Center(
        child: ElevatedButton(
          onPressed: () => context.go('/login'),
          child: const Text('Go to Login'),
        ),
      );
    }

    final String firstName = _userData?['firstName'] ?? '';
    final String lastName = _userData?['lastName'] ?? '';
    final String fullName = '$firstName $lastName'.trim();
    final String email = currentUser!.email ?? 'No Email';
    final String phone = _userData?['phoneNumber'] ?? 'Not set';
    final String? imageUrl = _userData?['profileImageUrl'];
    final String sex = _userData?['sex'] ?? _userData?['gender'] ?? 'Not set';
    final String address = _userData?['address'] ?? 'Not set';
    final Timestamp? dobTimestamp = _userData?['dateOfBirth'];
    final String dateOfBirth = _formatDate(dobTimestamp);
    const String displayRole = 'Owner';

    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: _fetchUserData,
        color: AppColors.primary,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              backgroundColor: Colors.white,
              elevation: 1,
              shadowColor: Colors.black.withOpacity(0.1),
              leading: const SizedBox.shrink(), 
              actions: [
                IconButton(
                  icon: const Icon(Iconsax.edit, color: AppColors.primary),
                  onPressed: () async {
                    final result = await context.push('/owner-edit-profile');
                    if (result == true) _fetchUserData();
                  },
                  tooltip: 'Edit Profile',
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _buildProfileHeader(
                  fullName,
                  email,
                  imageUrl,
                  displayRole,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    
                    _buildSectionHeader("Personal Information"),
                    const SizedBox(height: 16),
                    _buildCardContainer(
                      children: [
                        _buildInfoTile(
                          Iconsax.sms,
                          "Email Address",
                          email,
                        ),
                        _buildInfoTile(
                          Iconsax.call,
                          "Phone Number",
                          phone,
                        ),
                        _buildInfoTile(
                          Iconsax.cake,
                          "Date of Birth",
                          dateOfBirth,
                        ),
                        _buildInfoTile(
                          Iconsax.user,
                          "Sex",
                          sex,
                        ),
                        _buildInfoTile(
                          Iconsax.location,
                          "Current Address",
                          address,
                          isLast: true,
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    
                    _buildSectionHeader("Account & Settings"),
                    const SizedBox(height: 16),
                    _buildCardContainer(
                      children: [
                        _buildActionTile(
                          "Privacy Policy",
                          Iconsax.shield_tick,
                          () => context.go('/terms'),
                          isLast: true,
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    
                    _buildCardContainer(children: [_buildLogoutTile()]),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.textBody,
      ),
    );
  }

  Widget _buildProfileHeader(
    String fullName,
    String email,
    String? imageUrl,
    String displayRole,
  ) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 80, bottom: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.2),
                  spreadRadius: 4,
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage:
                  imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
              child: imageUrl == null
                  ? const Icon(
                      Iconsax.user,
                      size: 50,
                      color: AppColors.primary,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            fullName.isNotEmpty ? fullName : "Welcome, Owner",
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              displayRole,
              style: GoogleFonts.poppins(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContainer({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoTile(
    IconData icon,
    String title,
    String subtitle, {
    bool isLast = false,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          leading: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 25),
          ),
          title: Text(title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: AppColors.textBody,
                fontSize: 13,
              )),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                )),
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 85.0, right: 20),
            child: Divider(height: 1, thickness: 0.8, color: Colors.grey[200]),
          ),
      ],
    );
  }

  Widget _buildActionTile(
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool isLast = false,
  }) {
    return Column(
      children: [
        ListableInkWell(
          onTap: onTap,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            leading: Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 25),
            ),
            title: Text(title,
                style: GoogleFonts.poppins(
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
                fontSize: 15)),
            trailing: const Icon(Iconsax.arrow_right_3, color: Colors.grey),
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 85.0, right: 20),
            child: Divider(height: 1, thickness: 0.8, color: Colors.grey[200]),
          ),
      ],
    );
  }

  Widget _buildLogoutTile() {
    return ListableInkWell(
      onTap: _handleLogout,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Iconsax.logout, color: Colors.redAccent, size: 22),
        ),
        title: Text("Logout",
            style: GoogleFonts.poppins(
            color: Colors.redAccent,
            fontWeight: FontWeight.w600,
            fontSize: 15)),
        trailing:
            const Icon(Iconsax.arrow_right_3, color: Colors.redAccent),
      ),
    );
  }
}

class ListableInkWell extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const ListableInkWell({super.key, required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: child,
      ),
    );
  }
}
