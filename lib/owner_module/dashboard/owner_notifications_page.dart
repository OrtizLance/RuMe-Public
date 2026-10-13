


import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:rume/components/app_colors.dart';

class OwnerNotificationsPage extends StatelessWidget {
  const OwnerNotificationsPage({super.key});

  Future<void> _markAsRead(String notificationId, String userId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  Widget _buildNotificationBody(String body) {
    final defaultStyle = TextStyle(
      color: Colors.grey[800],
      fontSize: 14,
      height: 1.4,
    );
    final priceStyle = defaultStyle.copyWith(
      fontFamily: 'Roboto',
      fontWeight: FontWeight.bold,
      color: AppColors.blue900,
    );

    
    final priceRegex = RegExp(r'(₱\d{1,3}(,\d{3})*(\.\d+)?|\₱\d+(\.\d+)?)');
    final matches = priceRegex.allMatches(body);

    if (matches.isEmpty) {
      return Text(body, style: defaultStyle);
    }

    List<TextSpan> spans = [];
    int lastMatchEnd = 0;

    for (final match in matches) {
      
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: body.substring(lastMatchEnd, match.start)));
      }
      
      spans.add(TextSpan(text: match.group(0), style: priceStyle));
      lastMatchEnd = match.end;
    }

    
    if (lastMatchEnd < body.length) {
      spans.add(TextSpan(text: body.substring(lastMatchEnd)));
    }

    return RichText(text: TextSpan(style: defaultStyle, children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in')));
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: AppColors.blue900,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.blue900),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('notifications')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Notifications',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['read'] == true;
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: isRead ? 1 : 3,
                color: isRead ? Colors.white : Colors.blue.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.blue900.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.notifications, color: AppColors.blue900),
                  ),
                  title: Text(
                    data['title'] ?? 'Notification',
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      _buildNotificationBody(data['body'] ?? ''),
                      if (createdAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          DateFormat(
                            'MMM d, yyyy \'at\' h:mm a',
                          ).format(createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                  onTap: () {
                    if (!isRead) {
                      _markAsRead(doc.id, user.uid);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}