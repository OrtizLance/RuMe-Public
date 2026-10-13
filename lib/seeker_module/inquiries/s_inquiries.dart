
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/seeker_module/inquiries/seeker_chat.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SeekerInquiriesPage extends StatelessWidget {
  const SeekerInquiriesPage({super.key});

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return "";
    final dt = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inMinutes < 1) {
      return "Just now";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes}m";
    } else if (difference.inHours < 24) {
      return "${difference.inHours}h";
    } else if (dt.day == now.day &&
        dt.month == now.month &&
        dt.year == now.year) {
      return DateFormat.jm().format(dt);
    } else if (dt.year == now.year) {
      return DateFormat.MMMd().format(dt);
    } else {
      return DateFormat.yMMMd().format(dt);
    }
  }

  Future _deleteChat(BuildContext context, String chatId) async {
    final confirmed = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Chat'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this chat? This action cannot be undone.',
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

    if (confirmed != true) return;

    try {
      
      final messages = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      for (var msg in messages.docs) {
        await msg.reference.delete();
      }

      
      await FirebaseFirestore.instance.collection('chats').doc(chatId).delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Inquiries',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('seekerId', isEqualTo: user.uid)
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: AppColors.backgroundLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_off_outlined,
                      size: 50,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Something went wrong',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primaryColor,
                ),
              ),
            );
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: const BoxDecoration(
                      color: AppColors.backgroundLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 70,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "No conversations yet",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Start chatting with property owners\nto find your perfect place",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: AppColors.primaryColor.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: AppColors.primaryColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Browse properties to start chatting',
                          style: TextStyle(
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map;
              final propertyId = data['propertyId'];
              final ownerId = data['ownerId'];
              final lastMessage = data['lastMessage'] ?? '';
              final timeSent = _formatTimestamp(data['lastMessageTime']);
              final isUnread = data['unreadBySeeker'] ?? false;

              return StreamBuilder(
                stream: FirebaseFirestore.instance
                    .collection('properties')
                    .doc(propertyId)
                    .snapshots(),
                builder: (context, propSnapshot) {
                  String propertyName = "Property";
                  String? backgroundImageUrl;

                  if (propSnapshot.hasData && propSnapshot.data!.exists) {
                    final propData =
                        propSnapshot.data!.data() ??
                        {};
                    propertyName = propData['name'] ?? "Property";
                    backgroundImageUrl = propData['backgroundImageUrl'];
                  }

                  return StreamBuilder(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(ownerId)
                        .snapshots(),
                    builder: (context, ownerSnapshot) {
                      String ownerName = "Owner";

                      if (ownerSnapshot.hasData && ownerSnapshot.data!.exists) {
                        final ownerData =
                            ownerSnapshot.data!.data() ??
                            {};
                        final firstName = (ownerData['firstName'] ?? '')
                            .toString()
                            .trim();
                        final lastName = (ownerData['lastName'] ?? '')
                            .toString()
                            .trim();
                        if (firstName.isNotEmpty || lastName.isNotEmpty) {
                          ownerName = "$firstName $lastName".trim();
                        }
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              spreadRadius: 0,
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: isUnread
                                ? Border.all(
                                    color: AppColors.primaryColor.withOpacity(
                                      0.5,
                                    ),
                                    width: 1.5,
                                  )
                                : null,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Stack(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primaryColor,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primaryColor
                                            .withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child:
                                        backgroundImageUrl != null &&
                                            backgroundImageUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: backgroundImageUrl,
                                            fit: BoxFit.cover,
                                            width: 56,
                                            height: 56,
                                            placeholder: (context, url) =>
                                                const Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                ),
                                            errorWidget:
                                                (context, url, error) =>
                                                    Container(
                                                      child: const Icon(
                                                        Icons.home_work,
                                                        color: Colors.white,
                                                        size: 28,
                                                      ),
                                                    ),
                                          )
                                        : const Icon(
                                            Icons.home_work,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                  ),
                                ),
                                if (isUnread)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        propertyName,
                                        style: TextStyle(
                                          fontWeight: isUnread
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        ownerName,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  timeSent,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isUnread
                                        ? AppColors.primaryColor
                                        : Colors.grey.shade600,
                                    fontWeight: isUnread
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      lastMessage.isEmpty
                                          ? 'Start the conversation...'
                                          : lastMessage,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: lastMessage.isEmpty
                                            ? Colors.grey.shade400
                                            : (isUnread
                                                  ? Colors.black87
                                                  : Colors.grey.shade600),
                                        fontWeight:
                                            isUnread && lastMessage.isNotEmpty
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'delete') {
                                        _deleteChat(context, doc.id);
                                      }
                                    },
                                    icon: Icon(
                                      Icons.more_vert,
                                      color: Colors.grey.shade400,
                                      size: 20,
                                    ),
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                              size: 20,
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
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            onTap: () async {
                              
                              if (isUnread) {
                                await FirebaseFirestore.instance
                                    .collection('chats')
                                    .doc(doc.id)
                                    .update({'unreadBySeeker': false});
                              }

                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SeekerChatPage(
                                      chatId: doc.id,
                                      ownerId: ownerId,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
