
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:rume/components/input_field.dart';
import 'package:rume/components/app_colors.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class OwnerEditProfilePage extends StatefulWidget {
  const OwnerEditProfilePage({super.key});

  @override
  State<OwnerEditProfilePage> createState() => _OwnerEditProfilePageState();
}

class _OwnerEditProfilePageState extends State<OwnerEditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _phoneController = TextEditingController();
  final User? currentUser = FirebaseAuth.instance.currentUser;

  bool _isLoading = true;
  bool _isSaving = false;

  String? _currentImageUrl;
  File? _imageFile;

  String? _selectedSex;
  DateTime? _selectedDateOfBirth;
  String? _selectedAddress;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        _firstNameController.text = data['firstName'] ?? '';
        _lastNameController.text = data['lastName'] ?? '';
        _phoneController.text = data['phoneNumber'] ?? '';
        _selectedSex = data['sex'] ?? data['gender'];
        _selectedAddress = data["address"];
        _userRole = data['role'];

        if (data['dateOfBirth'] is Timestamp) {
          _selectedDateOfBirth = (data['dateOfBirth'] as Timestamp).toDate();
          _dobController.text = DateFormat(
            'yyyy-MM-dd',
          ).format(_selectedDateOfBirth!);
        }

        setState(() {
          _currentImageUrl = data['profileImageUrl'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          content: AwesomeSnackbarContent(
            title: 'Error',
            message: 'Failed to load your profile data. Please try again.',
            contentType: ContentType.failure,
          ),
        ));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    if (_userRole == null) return null;
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child(_userRole!)
          .child(currentUser!.email!)
          .child('profile_pictures')
          .child('profile.jpg');

      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (currentUser == null) return;

    setState(() => _isSaving = true);

    try {
      String? newImageUrl = _currentImageUrl;

      if (_imageFile != null) {
        newImageUrl = await _uploadImage(_imageFile!);
        if (newImageUrl == null) {
          throw Exception('Profile image upload failed.');
        }
      }

      final updatedData = {
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'profileImageUrl': newImageUrl,
        'sex': _selectedSex,
        "address": _selectedAddress,
        'dateOfBirth': _selectedDateOfBirth != null
            ? Timestamp.fromDate(_selectedDateOfBirth!)
            : null,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .update(updatedData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.transparent,
            content: AwesomeSnackbarContent(
              title: 'Success!',
              message: 'Your profile has been updated successfully.',
              contentType: ContentType.success,
            ),
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          content: AwesomeSnackbarContent(
              title: 'Update Failed',
              message: 'An error occurred while saving your profile: $e',
              contentType: ContentType.failure),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateOfBirth ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryColor, 
              onPrimary: Colors.white, 
              onSurface: Colors.black87, 
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryColor, 
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateOfBirth = picked;
        _dobController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<Map<String, dynamic>> loadAddressData() async {
    final String response = await rootBundle.loadString(
      'assets/ph_address.json',
    );
    return json.decode(response);
  }

  Future<void> _editAddressDialog() async {
    final addressData = await loadAddressData();

    String? region;
    String? province;
    String? city;
    String? barangay;

    
    

    List<String> regions = [addressData["region"]];
    List<String> provinces = [];
    List<String> cities = [];
    List<String> barangays = [];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
              ),
              backgroundColor: Colors.white,
              title: const Text(
                "Edit Address",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAddressDropdown('Select Region', region, regions, (
                      val,
                    ) {
                      setDialogState(() {
                        region = val;
                        province = null;
                        city = null;
                        barangay = null;
                        provinces = [addressData["province"]];
                        cities = [];
                        barangays = [];
                      });
                    }),
                    const SizedBox(height: 16.0),
                    _buildAddressDropdown(
                      'Select Province',
                      province,
                      provinces,
                      (val) {
                        setDialogState(() {
                          province = val;
                          city = null;
                          barangay = null;
                          cities = (addressData["cities"] as List)
                              .map((c) => c["name"] as String)
                              .toList();
                          barangays = [];
                        });
                      },
                    ),
                    const SizedBox(height: 16.0),
                    _buildAddressDropdown('Select City', city, cities, (val) {
                      setDialogState(() {
                        city = val;
                        barangay = null;
                        final cityData = (addressData["cities"] as List)
                            .firstWhere((c) => c["name"] == val);
                        barangays = List<String>.from(
                          cityData["barangays"] ?? [],
                        );
                      });
                    }),
                    const SizedBox(height: 16.0),
                    _buildAddressDropdown(
                      'Select Barangay',
                      barangay,
                      barangays,
                      (val) {
                        setDialogState(() => barangay = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (region != null &&
                        province != null &&
                        city != null &&
                        barangay != null) {
                      setState(() {
                        _selectedAddress =
                            "$barangay, $city, $province, $region";
                      });
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          elevation: 0,
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Colors.transparent,
                          content: AwesomeSnackbarContent(
                            title: 'Incomplete Address',
                            message: 'Please select all fields to set your address.',
                            contentType: ContentType.warning,
                          ),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                  child: const Text("Set Address"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  
  Widget _buildAddressDropdown(
    String hintText,
    String? value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: AppColors.backgroundLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.0),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.0),
          borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
        ),
      ),
      value: value,
      items: items
          .map((r) => DropdownMenuItem(value: r, child: Text(r)))
          .toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text(
          "Edit Profile",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primaryColor),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    
                    _buildProfileImageSelector(),
                    const SizedBox(height: 30),

                    
                    _buildSectionHeader("Personal Details"),
                    const SizedBox(height: 10),
                    _buildCardContainer(
                      children: [
                        CustomInputField(
                          controller: _firstNameController,
                          labelText: "First Name",
                          prefixIcon: Icons.person_outline,
                          validator: (val) =>
                              val!.isEmpty ? "Enter first name" : null,
                          inputFormatters: [],
                        ),
                        const SizedBox(height: 16),
                        CustomInputField(
                          controller: _lastNameController,
                          labelText: "Last Name",
                          prefixIcon: Icons.person_outline,
                          validator: (val) =>
                              val!.isEmpty ? "Enter last name" : null,
                          inputFormatters: [],
                        ),
                        const SizedBox(height: 16),
                        CustomInputField(
                          controller: _phoneController,
                          labelText: "Phone Number",
                          prefixIcon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          validator: (val) {
                            if (val == null || val.isEmpty) {
                              return "Enter phone number";
                            } else if (val.length != 11) {
                              return "Phone number must be exactly 11 digits";
                            } else if (!val.startsWith("09")) {
                              return "Phone number must start with 09";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildDatePickerField(),
                        const SizedBox(height: 16),
                        _buildSexDropdown(),
                        const SizedBox(height: 16),
                        _buildAddressListTile(),
                      ],
                    ),

                    const SizedBox(height: 40),

                    
                    Padding(
                      padding: const EdgeInsets.fromLTRB(60, 0, 60, 0),
                      child: SizedBox(
                        height: 60,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 8,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Text(
                                  "Save Changes",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade600,
      ),
      textAlign: TextAlign.start,
    );
  }

  Widget _buildCardContainer({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildProfileImageSelector() {
    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryColor, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryColor.withOpacity(0.2),
                    spreadRadius: 2,
                    blurRadius: 15,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 65,
                backgroundColor: AppColors.backgroundLight,
                backgroundImage: _imageFile != null
                    ? FileImage(_imageFile!)
                    : (_currentImageUrl != null
                              ? CachedNetworkImageProvider(_currentImageUrl!)
                              : null)
                          as ImageProvider?,
                child: (_imageFile == null && _currentImageUrl == null)
                    ? const Icon(Icons.person, size: 60, color: Colors.grey)
                    : null,
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePickerField() {
    return CustomInputField(
      controller: _dobController,
      labelText: "Date of Birth",
      prefixIcon: Symbols.cake,
      readOnly: true,
      onTap: _selectDate,
      validator: (val) => val!.isEmpty ? "Select date of birth" : null,
      inputFormatters: [],
    );
  }

  Widget _buildSexDropdown() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: "Sex",
        labelStyle: TextStyle(
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Icon(
          Icons.transgender_outlined,
          color: AppColors.primaryColor,
        ),
        fillColor: AppColors.backgroundLight,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
        ),
      ),
      value: _selectedSex,
      items: [
        "Male",
        "Female",
        "Other",
      ].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
      onChanged: (val) => setState(() => _selectedSex = val),
      validator: (val) => val == null ? "Select sex" : null,
    );
  }

  Widget _buildAddressListTile() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: ListTile(
        leading: const Icon(
          Icons.location_on_outlined,
          color: AppColors.primaryColor,
        ),
        title: const Text(
          "Current Address",
          style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          _selectedAddress ?? "Tap to set address",
          style: TextStyle(
            color: _selectedAddress == null ? Colors.redAccent : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.edit, color: AppColors.primaryColor),
        onTap: _editAddressDialog,
      ),
    );
  }
}