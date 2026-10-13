
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rume/owner_module/inquiries/owner_chat.dart';

class OwnerInquiriesPage extends StatefulWidget {
  const OwnerInquiriesPage({super.key});

  @override
  State<OwnerInquiriesPage> createState() => _OwnerInquiriesPageState();
}

class _OwnerInquiriesPageState extends State<OwnerInquiriesPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  String? _selectedPropertyId;
  List<DocumentSnapshot> _properties = [];

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadProperties() async {
    final user = FirebaseAuth.instance.currentUser!;
    final snapshot = await FirebaseFirestore.instance
        .collection('properties')
        .where('ownerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: false)
        .get();

    setState(() {
      _properties = snapshot.docs;
      if (_properties.isNotEmpty) {
        _selectedPropertyId = _properties.first.id;
        if (_properties.length <= 3) {
          _tabController = TabController(
            length: _properties.length,
            vsync: this,
          );
        }
      }
    });
  }

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

  Future<void> _deleteChat(BuildContext context, String chatId) async {
    final confirmed = await showDialog<bool>(
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

  Future<int> _getUnreadCountForProperty(String propertyId) async {
    final user = FirebaseAuth.instance.currentUser!;
    final chats = await FirebaseFirestore.instance
        .collection('chats')
        .where('ownerId', isEqualTo: user.uid)
        .where('propertyId', isEqualTo: propertyId)
        .where('unreadByOwner', isEqualTo: true)
        .get();

    return chats.docs.length;
  }

  void _showPropertySelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Switch Property',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    shrinkWrap: true,
                    itemCount: _properties.length,
                    itemBuilder: (context, index) {
                      final property = _properties[index];
                      final propertyData =
                          property.data() as Map<String, dynamic>;
                      final propertyName = propertyData['name'] ?? 'Property';
                      final backgroundImageUrl =
                          propertyData['backgroundImageUrl'];

                      return FutureBuilder<int>(
                        future: _getUnreadCountForProperty(property.id),
                        builder: (context, snapshot) {
                          final unreadCount = snapshot.data ?? 0;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedPropertyId = property.id;
                              });
                              Navigator.pop(context);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _selectedPropertyId == property.id
                                    ? Colors.blue[50]
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedPropertyId == property.id
                                      ? Colors.blueAccent
                                      : Colors.grey[300]!,
                                  width: _selectedPropertyId == property.id
                                      ? 2
                                      : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child:
                                            backgroundImageUrl != null &&
                                                backgroundImageUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: backgroundImageUrl,
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) =>
                                                    Container(
                                                      width: 60,
                                                      height: 60,
                                                      color: Colors.grey[300],
                                                      child: const Icon(
                                                        Icons.home_work,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                errorWidget:
                                                    (context, url, error) =>
                                                        Container(
                                                          width: 60,
                                                          height: 60,
                                                          color:
                                                              Colors.grey[300],
                                                          child: const Icon(
                                                            Icons.home_work,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                              )
                                            : Container(
                                                width: 60,
                                                height: 60,
                                                color: Colors.grey[300],
                                                child: const Icon(
                                                  Icons.home_work,
                                                  color: Colors.white,
                                                ),
                                              ),
                                      ),
                                      if (unreadCount > 0)
                                        Positioned(
                                          top: -4,
                                          right: -4,
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Text(
                                              unreadCount > 99
                                                  ? '99+'
                                                  : '$unreadCount',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      propertyName,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            _selectedPropertyId == property.id
                                            ? Colors.blueAccent
                                            : Colors.black87,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (_selectedPropertyId == property.id)
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.blueAccent,
                                      size: 24,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    if (_properties.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text(
            'Inquiries',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.blueAccent,
          elevation: 0,
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Inquiries',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_properties.length > 3)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .where('ownerId', isEqualTo: user.uid)
                    .where('propertyId', isEqualTo: _selectedPropertyId)
                    .snapshots(),
                builder: (context, snapshot) {
                  int unreadCount = 0;
                  if (snapshot.hasData) {
                    unreadCount = snapshot.data!.docs
                        .where(
                          (doc) =>
                              (doc.data() as Map)['unreadByOwner'] ?? false,
                        )
                        .length;
                  }

                  return Stack(
                    children: [
                      TextButton.icon(
                        onPressed: _showPropertySelectionDialog,
                        icon: const Icon(Icons.swap_horiz, color: Colors.white),
                        label: const Text(
                          'Switch Property',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
        bottom: _properties.length <= 3 && _tabController != null
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                tabs: _properties.map((property) {
                  final propertyData = property.data() as Map<String, dynamic>;
                  final propertyName = propertyData['name'] ?? 'Property';

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .where('ownerId', isEqualTo: user.uid)
                        .where('propertyId', isEqualTo: property.id)
                        .snapshots(),
                    builder: (context, snapshot) {
                      int unreadCount = 0;
                      if (snapshot.hasData) {
                        unreadCount = snapshot.data!.docs
                            .where(
                              (doc) =>
                                  (doc.data() as Map)['unreadByOwner'] ?? false,
                            )
                            .length;
                      }

                      return Tab(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Text(
                                propertyName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                top: -8,
                                right: -8,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    unreadCount > 99 ? '99+' : '$unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                }).toList(),
                onTap: (index) {
                  setState(() {
                    _selectedPropertyId = _properties[index].id;
                  });
                },
              )
            : null,
      ),
      body: _selectedPropertyId == null
          ? const Center(child: Text('No property selected'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('ownerId', isEqualTo: user.uid)
                  .where('propertyId', isEqualTo: _selectedPropertyId)
                  .orderBy('lastMessageTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
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
                        Text('Error: ${snapshot.error}'),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return Center(
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
                            Icons.message_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          "No inquiries yet",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Messages from seekers will appear here",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: docs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final seekerId = data['seekerId'];
                    final lastMessage = data['lastMessage'] ?? '';
                    final timeSent = _formatTimestamp(data['lastMessageTime']);
                    final isUnread = data['unreadByOwner'] ?? false;

                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(seekerId)
                          .snapshots(),
                      builder: (context, seekerSnapshot) {
                        String seekerName = "Seeker";
                        Map<String, dynamic> seekerData = {};

                        if (seekerSnapshot.hasData &&
                            seekerSnapshot.data!.exists) {
                          seekerData =
                              seekerSnapshot.data!.data()
                                  as Map<String, dynamic>? ??
                              {};
                          final firstName = (seekerData['firstName'] ?? '')
                              .toString()
                              .trim();
                          final lastName = (seekerData['lastName'] ?? '')
                              .toString()
                              .trim();
                          if (firstName.isNotEmpty || lastName.isNotEmpty) {
                            seekerName = "$firstName $lastName".trim();
                          }
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: isUnread
                                  ? LinearGradient(
                                      colors: [Colors.blue[50]!, Colors.white],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    )
                                  : null,
                              border: isUnread
                                  ? Border.all(
                                      color: Colors.blue[200]!,
                                      width: 1,
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
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.teal[300]!,
                                          Colors.teal[400]!,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.teal.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child:
                                          (seekerData['profileImageUrl'] !=
                                                  null &&
                                              (seekerData['profileImageUrl']
                                                      as String)
                                                  .isNotEmpty)
                                          ? CachedNetworkImage(
                                              imageUrl:
                                                  seekerData['profileImageUrl'],
                                              fit: BoxFit.cover,
                                              width: 56,
                                              height: 56,
                                              placeholder: (context, url) =>
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          Colors.teal[300]!,
                                                          Colors.teal[400]!,
                                                        ],
                                                      ),
                                                    ),
                                                    child: const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                    ),
                                                  ),
                                              errorWidget:
                                                  (
                                                    context,
                                                    url,
                                                    error,
                                                  ) => Container(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          Colors.teal[300]!,
                                                          Colors.teal[400]!,
                                                        ],
                                                      ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.person,
                                                      color: Colors.white,
                                                      size: 28,
                                                    ),
                                                  ),
                                            )
                                          : const Icon(
                                              Icons.person,
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
                                        width: 16,
                                        height: 16,
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
                                    child: Text(
                                      seekerName,
                                      style: TextStyle(
                                        fontWeight: isUnread
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    timeSent,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isUnread
                                          ? Colors.blue[700]
                                          : Colors.grey[600],
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
                                            ? 'No messages yet'
                                            : lastMessage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: lastMessage.isEmpty
                                              ? Colors.grey[400]
                                              : (isUnread
                                                    ? Colors.black87
                                                    : Colors.grey[600]),
                                          fontWeight: isUnread
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
                                        color: Colors.grey[400],
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
                                                'Delete Chat',
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
                                      .update({'unreadByOwner': false});
                                }

                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => OwnerChatPage(
                                        chatId: doc.id,
                                        seekerId: seekerId,
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
            ),
    );
  }
}