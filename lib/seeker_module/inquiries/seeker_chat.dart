
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:rume/components/app_colors.dart';

class SeekerChatPage extends StatefulWidget {
  final String chatId;
  final String ownerId;
  final String? autoSendRoomId;
  final Map<String, dynamic>? autoSendRoomData;

  const SeekerChatPage({
    super.key,
    required this.chatId,
    required this.ownerId,
    this.autoSendRoomId,
    this.autoSendRoomData,
  });

  @override
  State<SeekerChatPage> createState() => _SeekerChatPageState();
}

class _SeekerChatPageState extends State<SeekerChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasAutoSent = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoSendRoomId != null && widget.autoSendRoomData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSendRoomDetails();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _autoSendRoomDetails() async {
    if (_hasAutoSent) return;
    _hasAutoSent = true;

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final roomData = widget.autoSendRoomData!;

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
            'senderId': user.uid,
            'type': 'room_inquiry',
            'roomId': widget.autoSendRoomId,
            'roomData': {
              'name': roomData['name'],
              'price': roomData['price'],
              'capacity': roomData['capacity'],
              'description': roomData['description'],
              'status': roomData['status'],
              'images': roomData['images'],
            },
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'sentAt': FieldValue.serverTimestamp(),
            'readAt': null,
          });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastMessage': 'Sent room inquiry',
            'lastMessageTime': FieldValue.serverTimestamp(),
            'unreadByOwner': true,
            'unreadBySeeker': false,
          });

      _scrollToBottom();
    } catch (e) {
      debugPrint('Error auto-sending room details: $e');
    }
  }

  Future<void> _sendMessage({String? text, File? imageFile}) async {
    if ((text?.trim().isEmpty ?? true) && imageFile == null) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      String? imageUrl;

      if (imageFile != null) {
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';
        final ref = FirebaseStorage.instance.ref().child(
          'chat_images/${widget.chatId}/$fileName',
        );

        await ref.putFile(imageFile);
        imageUrl = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
            'senderId': user.uid,
            'type': 'text',
            'text': text?.trim(),
            'imageUrl': imageUrl,
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'sentAt': FieldValue.serverTimestamp(),
            'readAt': null,
          });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastMessage': text?.trim() ?? '📷 Image',
            'lastMessageTime': FieldValue.serverTimestamp(),
            'unreadByOwner': true,
            'unreadBySeeker': false,
          });

      _controller.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1080,
        maxHeight: 1080,
      );

      if (pickedFile != null) {
        await _sendMessage(imageFile: File(pickedFile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatMessageTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    final now = DateTime.now();

    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return DateFormat.jm().format(dt);
    } else if (dt.year == now.year) {
      return DateFormat.MMMd().add_jm().format(dt);
    } else {
      return DateFormat.yMMMd().add_jm().format(dt);
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final messages = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .where('isRead', isEqualTo: false)
          .where(
            'senderId',
            isNotEqualTo: FirebaseAuth.instance.currentUser!.uid,
          )
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in messages.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    
    _markMessagesAsRead();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .snapshots(),
          builder: (context, chatSnapshot) {
            if (!chatSnapshot.hasData) {
              return AppBar(
                backgroundColor: AppColors.primaryColor,
                title: const Text(
                  "Loading...",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }

            final chatData = chatSnapshot.data!.data() as Map<String, dynamic>?;
            final propertyId = chatData?['propertyId'];

            if (propertyId == null) {
              return AppBar(
                backgroundColor: AppColors.primaryColor,
                title: const Text(
                  "Chat",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('properties')
                  .doc(propertyId)
                  .snapshots(),
              builder: (context, propSnapshot) {
                String propertyName = 'Property';
                String? backgroundImageUrl;

                if (propSnapshot.hasData && propSnapshot.data!.exists) {
                  final propData =
                      propSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                  propertyName = propData['name'] ?? 'Property';
                  backgroundImageUrl = propData['backgroundImageUrl'];
                }

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.ownerId)
                      .snapshots(),
                  builder: (context, ownerSnapshot) {
                    String ownerName = "Owner";

                    if (ownerSnapshot.hasData && ownerSnapshot.data!.exists) {
                      final ownerData =
                          ownerSnapshot.data!.data() as Map<String, dynamic>? ??
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

                    return AppBar(
                      backgroundColor: AppColors.primaryColor,
                      elevation: 2,
                      titleSpacing: 0,
                      shadowColor: Colors.teal.withOpacity(0.5),
                      title: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (backgroundImageUrl != null &&
                                  backgroundImageUrl.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      backgroundColor: Colors.black,
                                      appBar: AppBar(
                                        backgroundColor: Colors.black,
                                        iconTheme: const IconThemeData(
                                          color: Colors.white,
                                        ),
                                        title: Text(
                                          propertyName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      body: Center(
                                        child: InteractiveViewer(
                                          child: CachedNetworkImage(
                                            imageUrl: backgroundImageUrl ?? '',
                                            fit: BoxFit.contain,
                                            placeholder: (context, url) =>
                                                const Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.white,
                                                      ),
                                                ),
                                            errorWidget:
                                                (context, url, error) =>
                                                    const Icon(
                                                      Icons.broken_image,
                                                      color: Colors.white,
                                                      size: 50,
                                                    ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
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
                                        width: 40,
                                        height: 40,
                                        placeholder: (context, url) =>
                                            Container(
                                              color: Colors.grey[300],
                                              child: const Icon(
                                                Icons.home_work,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            Container(
                                              color: Colors.grey[300],
                                              child: const Icon(
                                                Icons.home_work,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                      )
                                    : Container(
                                        color: Colors.grey[300],
                                        child: const Icon(
                                          Icons.home_work,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  propertyName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  ownerName,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
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

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline,
                            size: 50,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Start the conversation',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Send your first message below',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data() as Map<String, dynamic>;
                    final isMe =
                        data['senderId'] ==
                        FirebaseAuth.instance.currentUser!.uid;
                    final messageType = data['type'] ?? 'text';

                    if (messageType == 'room_inquiry') {
                      return _buildRoomInquiryMessage(data, isMe);
                    }

                    return _buildTextMessage(data, isMe);
                  },
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isLoading ? null : _pickImage,
                    icon: Icon(
                      Icons.photo_camera,
                      color: _isLoading ? Colors.grey : AppColors.primaryColor,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: "Type a message...",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        maxLines: 4,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty && !_isLoading) {
                            _sendMessage(text: value.trim());
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: AppColors.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              if (_controller.text.trim().isNotEmpty) {
                                _sendMessage(text: _controller.text.trim());
                              }
                            },
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomInquiryMessage(Map<String, dynamic> data, bool isMe) {
    final roomData = data['roomData'] as Map<String, dynamic>?;
    if (roomData == null) return const SizedBox.shrink();

    final images = List<String>.from(roomData['images'] ?? []);
    final roomName = roomData['name'] ?? 'Room';
    final price = roomData['price']?.toString() ?? '0';
    final capacity = roomData['capacity']?.toString() ?? '1';
    final description = roomData['description'] ?? '';
    final status = roomData['status'] ?? 'available';
    final timestamp = data['timestamp'] as Timestamp?;
    final isRead = data['isRead'] ?? false;

    Color statusColor;
    switch (status) {
      case 'available':
        statusColor = Colors.green;
        break;
      case 'occupied':
        statusColor = Colors.red;
        break;
      case 'on_hold':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.grey[300]!, Colors.grey[400]!],
                ),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              decoration: BoxDecoration(
                color: isMe ? AppColors.primaryColor : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  if (images.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                      ),
                      child: SizedBox(
                        height: 150,
                        child: PageView.builder(
                          itemCount: images.length,
                          itemBuilder: (context, index) {
                            return CachedNetworkImage(
                              imageUrl: images[index],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                roomName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isMe ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                status == 'on_hold'
                                    ? 'ON HOLD'
                                    : status.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '₱$price/month',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 15,
                            color: isMe ? Colors.white : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.people,
                              size: 14,
                              color: isMe ? Colors.white70 : Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Max Capacity: $capacity pax',
                              style: TextStyle(
                                fontSize: 13,
                                color: isMe ? Colors.white70 : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              color: isMe ? Colors.white70 : Colors.grey[700],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (timestamp != null)
                              Text(
                                _formatMessageTime(timestamp),
                                style: TextStyle(
                                  color: isMe
                                      ? Colors.white70
                                      : Colors.grey[500],
                                  fontSize: 11,
                                ),
                              ),
                            if (isMe && isRead)
                              Row(
                                children: [
                                  Icon(
                                    Icons.done_all,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Seen',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryColor,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextMessage(Map<String, dynamic> data, bool isMe) {
    final timestamp = data['timestamp'] as Timestamp?;
    final text = data['text'] as String?;
    final imageUrl = data['imageUrl'] as String?;
    final isRead = data['isRead'] ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.grey[300]!, Colors.grey[400]!],
                ),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isMe ? AppColors.primaryColor : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: text != null
                            ? Radius.zero
                            : Radius.circular(isMe ? 18 : 4),
                        bottomRight: text != null
                            ? Radius.zero
                            : Radius.circular(isMe ? 4 : 18),
                      ),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                backgroundColor: Colors.black,
                                appBar: AppBar(
                                  backgroundColor: Colors.black,
                                  iconTheme: const IconThemeData(
                                    color: Colors.white,
                                  ),
                                ),
                                body: Center(
                                  child: InteractiveViewer(
                                    child: CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.contain,
                                      placeholder: (context, url) =>
                                          const Center(
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                            ),
                                          ),
                                      errorWidget: (context, url, error) =>
                                          const Icon(
                                            Icons.broken_image,
                                            color: Colors.white,
                                            size: 50,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 200,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 200,
                            height: 150,
                            color: Colors.grey[200],
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.teal,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 200,
                            height: 150,
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (text != null && text.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        text,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontSize: 16,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: 8,
                      top: text != null ? 0 : 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (timestamp != null)
                          Text(
                            _formatMessageTime(timestamp),
                            style: TextStyle(
                              color: isMe ? Colors.white70 : Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        if (isMe && isRead) ...[
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.done_all,
                                size: 14,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Seen',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryColor,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}