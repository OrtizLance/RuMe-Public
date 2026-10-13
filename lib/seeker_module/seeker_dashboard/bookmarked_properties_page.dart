import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/seeker_module/properties/property_rooms_page.dart';

class BookmarkedPropertiesPage extends StatefulWidget {
  const BookmarkedPropertiesPage({super.key});

  @override
  State<BookmarkedPropertiesPage> createState() =>
      _BookmarkedPropertiesPageState();
}

class _BookmarkedPropertiesPageState extends State<BookmarkedPropertiesPage> {
  late Future<List<DocumentSnapshot>> _bookmarkedPropertiesFuture;

  @override
  void initState() {
    super.initState();
    _bookmarkedPropertiesFuture = _fetchBookmarkedProperties();
  }

  Future<List<DocumentSnapshot>> _fetchBookmarkedProperties() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return [];
    }

    
    final bookmarksSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('bookmarks')
        .get();

    final propertyIds = bookmarksSnapshot.docs.map((doc) => doc.id).toList();

    if (propertyIds.isEmpty) {
      return [];
    }

    
    final propertiesSnapshot = await FirebaseFirestore.instance
        .collection('properties')
        .where(FieldPath.documentId, whereIn: propertyIds)
        .where('status', whereIn: ['verified', 'approved']) 
        .get();

    return propertiesSnapshot.docs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'My Bookmarks',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.blue900,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
      ),
      body: FutureBuilder<List<DocumentSnapshot>>(
        future: _bookmarkedPropertiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final properties = snapshot.data;

          if (properties == null || properties.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bookmark_remove_outlined,
                      size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No Bookmarks Yet',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your saved properties will appear here.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: properties.length,
            itemBuilder: (context, index) {
              final propertyDoc = properties[index];
              final data = propertyDoc.data() as Map<String, dynamic>;
              final imageUrl = data['backgroundImageUrl'] as String?;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PropertyRoomsPage(propertyId: propertyDoc.id),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: (imageUrl != null && imageUrl.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                height: 150,
                                color: Colors.grey[300],
                                child: const Icon(Icons.home_work, size: 50),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['name'] ?? 'Unnamed Property',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['address'] ?? 'No address',
                              style: TextStyle(color: Colors.grey[600]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}