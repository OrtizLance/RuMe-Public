
import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';

class RoomFormPage extends StatefulWidget {
  final String propertyId;
  final String? roomId;
  final bool isReverifying;

  const RoomFormPage({
    super.key,
    required this.propertyId,
    this.roomId,
    this.isReverifying = false, 
  });

  @override
  State<RoomFormPage> createState() => _RoomFormPageState();
}

class _RoomFormPageState extends State<RoomFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _roomNameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  bool _isSaving = false;

  String _status = 'available';
  final Set<String> _selectedAmenities = {};
  Map<String, List<String>> _categorizedAmenities = {};

  int _capacity = 1;
  List<File> _newImages = [];
  List<String> _existingImageUrls = [];

  User? _user;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  Future<void> _initializeForm() async {
    setState(() => _isLoading = true);
    _user = FirebaseAuth.instance.currentUser;

    await _loadAmenities();

    if (widget.roomId != null) {
      await _loadRoomData();
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadAmenities() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/amenities.json',
      );
      final Map<String, dynamic> data = json.decode(jsonString);
      final amenitiesData = data['amenities'] as Map<String, dynamic>;

      setState(() {
        _categorizedAmenities = amenitiesData.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        );
      });
    } catch (e) {
      debugPrint('Error loading amenities: $e');
    }
  }

  Future<void> _loadRoomData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .doc(widget.roomId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _roomNameCtrl.text = data['name'] ?? '';
        _priceCtrl.text = (data['price'] ?? '').toString();
        _descriptionCtrl.text = data['description'] ?? '';
        _status = data['status'] ?? 'available';
        _capacity = data['capacity'] ?? 1;

        final amenities = List<String>.from(data['amenities'] ?? []);
        _selectedAmenities.addAll(amenities);
        _existingImageUrls = List<String>.from(data['images'] ?? []);
      }
    } catch (e) {
      debugPrint('Error loading room: $e');
    }
  }

  @override
  void dispose() {
    _roomNameCtrl.dispose();
    _priceCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) {
      setState(() {
        _newImages.addAll(picked.map((xFile) => File(xFile.path)));
      });
    }
  }

  Future<List<String>> _uploadImages(String roomId) async {
    final List<String> urls = [];
    for (final file in _newImages) {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final ref = FirebaseStorage.instance.ref().child(
        
        'room_images/${_user!.uid}/${widget.propertyId}/$roomId/$fileName',
      );
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }

  Future<void> _removeExistingImage(String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Image'),
        content: const Text('Remove this image permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (e) {
        debugPrint('Failed to delete image: $e');
      }
      setState(() => _existingImageUrls.remove(url));
    }
  }

  Future<void> _showAmenitiesSelector() async {
    final result = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AmenitiesSelectorScreen(
          categorizedAmenities: _categorizedAmenities,
          selectedAmenities: Set.from(_selectedAmenities),
        ),
        fullscreenDialog: true,
      ),
    );

    if (result != null) {
      setState(() {
        _selectedAmenities.clear();
        _selectedAmenities.addAll(result);
      });
    }
  }

  Future<void> _saveRoom() async {
    if (!_formKey.currentState!.validate()) return;
    if (_user == null) return;

    setState(() => _isSaving = true);

    try {
      final roomsCol = FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms');

      final docRef = widget.roomId != null
          ? roomsCol.doc(widget.roomId)
          : roomsCol.doc();

      final String newRoomId = docRef.id;

      List<String> finalImageUrls = List<String>.from(_existingImageUrls);

      if (_newImages.isNotEmpty) {
        final uploaded = await _uploadImages(newRoomId);
        finalImageUrls.addAll(uploaded);
      }

      final isNewRoom = widget.roomId == null;

      final roomData = {
        'ownerId': _user!.uid,
        'propertyId': widget.propertyId,
        'name': _roomNameCtrl.text.trim(),
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
        'description': _descriptionCtrl.text.trim(),
        'amenities': _selectedAmenities.toList(),
        'capacity': _capacity,
        'status': _status, 
        
        'verificationStatus': widget.isReverifying
            ? 'reverify'
            : (isNewRoom ? 'pending' : null),
        'images': finalImageUrls,
        'createdAt': isNewRoom ? FieldValue.serverTimestamp() : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      
      roomData.removeWhere((key, value) => value == null);

      await docRef.set(roomData, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.roomId != null
                  ? (widget.isReverifying
                        ? 'Room updated for reverification!'
                        : 'Room updated successfully')
                  : 'Room created successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save room: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 22),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _existingImageUrls.length + _newImages.length + 1,
      itemBuilder: (context, index) {
        
        if (index == 0) {
          return GestureDetector(
            onTap: _pickImages,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!, width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Iconsax.gallery_add, size: 32, color: Colors.grey[600]),
                  const SizedBox(height: 8),
                  Text(
                    'Add Image',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        
        if (index - 1 < _existingImageUrls.length) {
          final url = _existingImageUrls[index - 1];
          return _buildImageTile(
            image: CachedNetworkImageProvider(url),
            onRemove: () => _removeExistingImage(url),
          );
        }

        
        final newImageIndex = index - 1 - _existingImageUrls.length;
        final file = _newImages[newImageIndex];
        return _buildImageTile(
          image: FileImage(file),
          onRemove: () => setState(() => _newImages.remove(file)),
        );
      },
    );
  }

  Widget _buildImageTile({
    required ImageProvider image,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(
            image: image,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmenitiesSection() {
    return GestureDetector(
      onTap: _showAmenitiesSelector,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Iconsax.magic_star, color: Colors.blueAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Amenities',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedAmenities.isEmpty
                        ? 'Tap to select amenities'
                        : '${_selectedAmenities.length} selected',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blueAccent),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.roomId != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Room' : 'Create New Room',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                children: [
                  _buildSectionHeader('Room Details', Iconsax.edit),
                  TextFormField(
                    controller: _roomNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Room Name',
                      hintText: 'e.g., Room 101, Deluxe Room',
                      prefixIcon: const Icon(
                        Iconsax.tag,
                        color: Colors.blueAccent,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) => v?.trim().isEmpty ?? true
                        ? 'Room name is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Monthly Rent',
                      hintText: '0.00',
                      prefixIcon: const Icon(
                        Iconsax.money_3,
                        color: Colors.blueAccent,
                      ),
                      prefixText: '₱ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    style: const TextStyle(fontFamily: 'Roboto', fontSize: 17),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Price is required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Description (Optional)',
                      hintText: 'Describe the room features...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 25),
                  _buildSectionHeader('Settings', Iconsax.setting_2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildDropdown<int>(
                          label: 'Capacity',
                          icon: Iconsax.people,
                          value: _capacity,
                          items: List.generate(10, (i) => i + 1).map((n) {
                            return DropdownMenuItem(
                              value: n,
                              child: Text('$n ${n == 1 ? 'pax' : 'pax'}'),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => _capacity = v!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildDropdown<String>(
                          label: 'Status',
                          icon: Iconsax.activity,
                          value: _status,
                          items: ['available', 'occupied', 'on_hold']
                              .where((status) {
                                if (status == 'on_hold' &&
                                    _status != 'on_hold') {
                                  return false;
                                }
                                return true;
                              })
                              .map((status) {
                                String displayText;
                                switch (status) {
                                  case 'available':
                                    displayText = 'Available';
                                    break;
                                  case 'on_hold':
                                    displayText = 'On Hold';
                                    break;
                                  case 'occupied':
                                  default:
                                    displayText = 'Occupied';
                                    break;
                                }
                                return DropdownMenuItem(
                                  value: status,
                                  child: Text(displayText),
                                );
                              })
                              .toList(),
                          onChanged: (v) => setState(() => _status = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildAmenitiesSection(),
                  const SizedBox(height: 20),
                  _buildSectionHeader('Room Images', Iconsax.gallery),
                  _buildImageGrid(),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 50,

                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveRoom,
                      icon: _isSaving
                          ? const SizedBox.shrink()
                          : const Icon(
                              Iconsax.add_square,
                              color: Colors.white,
                              size: 30,
                            ),
                      label: _isSaving
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              isEditing ? 'Update Room' : 'Create Room',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}



class AmenitiesSelectorScreen extends StatefulWidget {
  final Map<String, List<String>> categorizedAmenities;
  final Set<String> selectedAmenities;

  const AmenitiesSelectorScreen({
    super.key,
    required this.categorizedAmenities,
    required this.selectedAmenities,
  });

  @override
  State<AmenitiesSelectorScreen> createState() =>
      _AmenitiesSelectorScreenState();
}

class _AmenitiesSelectorScreenState extends State<AmenitiesSelectorScreen> {
  late Set<String> _tempSelected;
  late Map<String, List<String>> _localCategorizedAmenities;
  final _customAmenityController = TextEditingController();

  @override
  void initState() {
    
    super.initState();
    _tempSelected = Set.from(widget.selectedAmenities);
    _localCategorizedAmenities = Map.from(widget.categorizedAmenities);
    if (!_localCategorizedAmenities.containsKey('custom')) {
      _localCategorizedAmenities['custom'] = [];
    }
    
    _tempSelected.forEach((amenity) {
      if (!_isPredefined(amenity)) {
        if (!_localCategorizedAmenities['custom']!.contains(amenity)) {
          _localCategorizedAmenities['custom']!.add(amenity);
        }
      }
    });
  }

  String _getCategoryDisplayName(String key) {
    
    return key[0].toUpperCase() + key.substring(1);
  }

  @override
  void dispose() {
    _customAmenityController.dispose();
    super.dispose();
  }

  bool _isPredefined(String amenity) {
    
    for (var category in widget.categorizedAmenities.keys) {
      if (widget.categorizedAmenities[category]!.contains(amenity)) {
        return true;
      }
    }
    return false;
  }

  void _addCustomAmenity() {
    
    final newAmenity = _customAmenityController.text.trim();
    if (newAmenity.isNotEmpty) {
      setState(() {
        if (!_localCategorizedAmenities['custom']!.contains(newAmenity)) {
          _localCategorizedAmenities['custom']!.add(newAmenity);
        }
        
        _tempSelected.add(newAmenity);
        _customAmenityController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Select Amenities',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, _tempSelected);
            },
            child: const Text(
              'Done',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue[50],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_tempSelected.length} amenities selected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[900],
                  ),
                ),
                if (_tempSelected.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _tempSelected.clear();
                      });
                    },
                    child: const Text('Clear All'),
                  ),
              ],
            ),
          ),
          
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              itemCount: _localCategorizedAmenities.length,
              itemBuilder: (context, index) {
                final category = _localCategorizedAmenities.keys.elementAt(
                  index,
                );
                final amenities = _localCategorizedAmenities[category]!;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getCategoryDisplayName(category),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: amenities.map((amenity) { 
                            final isCustom = category == 'custom';
                            final isSelected = _tempSelected.contains(amenity);
                            return FilterChip(
                              label: Text(amenity),
                              selected: isSelected, 
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _tempSelected.add(amenity);
                                  } else {
                                    _tempSelected.remove(amenity);
                                  }
                                });
                              },
                              selectedColor: isCustom ? Colors.green[100] : Colors.blue[100],
                              checkmarkColor: isCustom ? Colors.green[800] : Colors.blue[700],
                              backgroundColor: isCustom ? Colors.green[50] : Colors.grey[50],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isSelected
                                      ? (isCustom
                                          ? Colors.green[700]!
                                          : Colors.blue[700]!)
                                      : Colors.grey[300]!,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                )
              ],
            ),
            child: TextFormField(
              controller: _customAmenityController,
              decoration: InputDecoration(
                labelText: 'Create a Custom Amenity',
                hintText: 'e.g., Study Table, Bookshelf...',
                prefixIcon: const Icon(Icons.add_circle_outline, color: Colors.green),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _addCustomAmenity,
                  tooltip: 'Add Amenity',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onFieldSubmitted: (_) => _addCustomAmenity(),
            ),
          ),
        ],
      ),
    );
  }
}
