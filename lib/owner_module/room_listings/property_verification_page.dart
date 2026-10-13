
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iconsax/iconsax.dart';
import 'package:camera/camera.dart';

import 'dart:async';

import 'package:rume/components/app_colors.dart';

class PropertyVerificationPage extends StatefulWidget {
  const PropertyVerificationPage({super.key});

  @override
  State<PropertyVerificationPage> createState() =>
      _PropertyVerificationPageState();
}

class _PropertyVerificationPageState extends State<PropertyVerificationPage> {
  int _currentStep = 0;
  final _propertyNameController = TextEditingController();

  
  LatLng? _selectedLocation;
  String? _locationAddress;
  File? _propertyFrontImage;

  
  File? _businessPermitImage;
  File? _validIdFrontImage;
  File? _validIdBackImage;

  
  CameraController? _cameraController;
  List<File> _capturedFaces = [];
  String _faceInstruction = "Face forward";
  int _faceCaptureStep = 0;
  bool _isProcessingFace = false;
  FaceDetector? _faceDetector;
  Timer? _faceDetectionTimer;

  
  String? _selectedRegion;
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedBarangay;

  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _initializeCamera();
  }

  @override
  void dispose() {
    _propertyNameController.dispose();
    _cameraController?.dispose();
    _faceDetector?.close();
    _faceDetectionTimer?.cancel();
    super.dispose();
  }

  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        minFaceSize: 0.15,
      ),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final frontCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );

        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );

        await _cameraController!.initialize();
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  Future<void> _showExpandedMap() async {
    GoogleMapController? mapController;
    LatLng? tempLocation = _selectedLocation;
    String? tempLocationAddress = _locationAddress;
    bool isLoadingAddress = false;

    
    Future<void> updateAddressFromLocation(
      LatLng location,
      StateSetter setMapState,
    ) async {
      setMapState(() {
        isLoadingAddress = true;
      });

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          location.latitude,
          location.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks[0];
          tempLocationAddress =
              '${place.street ?? ''}, ${place.locality ?? ''}, ${place.country ?? ''}'
                  .replaceAll(RegExp(r',\s*,?'), ',')
                  .trim();

          setMapState(() {
            isLoadingAddress = false;
          });
        }
      } catch (e) {
        debugPrint('Reverse geocoding failed: $e');
        setMapState(() {
          isLoadingAddress = false;
        });
      }
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setMapState) {
            return Scaffold(
              appBar: AppBar(
                centerTitle: true,
                title: Text(
                  "Set Property",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.onSurfaceGray,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: Colors.blue,
                actions: [
                  TextButton(
                    onPressed: () {
                      
                      Navigator.pop(context, {
                        'location': tempLocation,
                        'address': tempLocationAddress,
                      });
                    },
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ],
              ),
              body: Stack(
                children: [
                  GoogleMap(
                    mapType: MapType.hybrid,
                    initialCameraPosition: CameraPosition(
                      target: tempLocation ?? const LatLng(6.5003, 124.8435),
                      zoom: 17.0,
                    ),
                    markers: tempLocation != null
                        ? {
                            Marker(
                              markerId: const MarkerId('property'),
                              position: tempLocation!,
                              draggable: true,
                              onDragEnd: (newPosition) {
                                setMapState(() {
                                  tempLocation = newPosition;
                                });
                                
                                updateAddressFromLocation(
                                  newPosition,
                                  setMapState,
                                );
                              },
                            ),
                          }
                        : {},
                    onTap: (position) {
                      setMapState(() {
                        tempLocation = position;
                      });
                      
                      updateAddressFromLocation(position, setMapState);
                    },
                    onMapCreated: (GoogleMapController controller) {
                      mapController = controller;
                    },
                  ),
                  Positioned(
                    bottom: 80,
                    left: 20,
                    right: 20,
                    child: ElevatedButton.icon(
                      onPressed: isLoadingAddress
                          ? null
                          : () async {
                              
                              if (!context.mounted) return;

                              setMapState(() => _isLoading = true);
                              try {
                                LocationPermission permission =
                                    await Geolocator.checkPermission();
                                if (permission == LocationPermission.denied) {
                                  permission =
                                      await Geolocator.requestPermission();
                                  if (permission == LocationPermission.denied) {
                                    _showErrorSnackBar(
                                      'Location permissions are denied',
                                    );
                                    return;
                                  }
                                }

                                final position =
                                    await Geolocator.getCurrentPosition(
                                      desiredAccuracy: LocationAccuracy.high,
                                    );

                                final latLng = LatLng(
                                  position.latitude,
                                  position.longitude,
                                );

                                try {
                                  List<Placemark> placemarks =
                                      await placemarkFromCoordinates(
                                        latLng.latitude,
                                        latLng.longitude,
                                      );
                                  if (placemarks.isNotEmpty) {
                                    final place = placemarks[0];
                                    _locationAddress =
                                        '${place.street ?? ''}, ${place.locality ?? ''}, ${place.country ?? ''}'
                                            .replaceAll(RegExp(r',\s*,?'), ',')
                                            .trim();
                                  }
                                } catch (_) {
                                  debugPrint('Reverse geocoding failed');
                                }

                                setMapState(() {
                                  tempLocation = latLng;
                                });

                                
                                if (mapController != null) {
                                  mapController!.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      CameraPosition(
                                        target: latLng,
                                        zoom: 17.0,
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                _showErrorSnackBar(
                                  'Failed to get location: $e',
                                );
                              } finally {
                                if (context.mounted) {
                                  setMapState(() => _isLoading = false); 
                                }
                              }
                            },
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('Get Current Location'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Tap the map or drag the marker to set your property location',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (tempLocationAddress != null) ...[
                            const SizedBox(height: 8),
                            const Divider(),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    tempLocationAddress!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (isLoadingAddress)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Getting address...',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedLocation = result['location'];
        _locationAddress = result['address'];
      });
    }
  }

  Future<void> _pickPropertyFrontImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (pickedFile != null) {
      setState(() {
        _propertyFrontImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _pickDocument(String type) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      
      if (file.lengthSync() > 10 * 1024 * 1024) {
        
        _showErrorSnackBar('File size cannot exceed 10MB.');
        return;
      }

      setState(() {
        switch (type) {
          case 'business':
            _businessPermitImage = file;
            break;
          case 'id_front':
            _validIdFrontImage = file;
            break;
          case 'id_back':
            _validIdBackImage = file;
            break;
        }
      });
    }
  }

  void _startAutoFaceCapture() {
    if (_isProcessingFace) return;

    _faceDetectionTimer?.cancel();
    _faceDetectionTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) => _detectAndCaptureFace(),
    );
  }

  void _stopAutoFaceCapture() {
    _faceDetectionTimer?.cancel();
    setState(() {}); 
  }

  Future<void> _detectAndCaptureFace() async {
    if (_isProcessingFace ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _faceCaptureStep >= 1) {
      return;
    }

    setState(() => _isProcessingFace = true);

    try {
      final XFile image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final List<Face> faces = await _faceDetector!.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        bool shouldCapture = false;

        
        if (_faceCaptureStep == 0) {
          
          final headEulerAngleY = face.headEulerAngleY ?? 0;
          shouldCapture = headEulerAngleY.abs() < 15;
        }

        if (shouldCapture) {
          final capturedFile = File(image.path);
          setState(() {
            _capturedFaces.add(capturedFile);
            _faceCaptureStep++;
            _faceInstruction = "Face scan complete!";
            _stopAutoFaceCapture();
          });

          
          if (_faceCaptureStep >= 1 && mounted) {
            
            
            await Future.delayed(const Duration(milliseconds: 1500));
            await Future.delayed(const Duration(seconds: 1));
            if (mounted) {
              setState(() => _currentStep = 3);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    } finally {
      if (mounted) setState(() => _isProcessingFace = false);
    }
  }

  Future<Map<String, dynamic>> _loadAddressData() async {
    final String response = await rootBundle.loadString(
      'assets/ph_address.json',
    );
    return json.decode(response);
  }

  Future<void> _submitVerificationRequest() async {
    setState(() => _isLoading = true);
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      _showErrorSnackBar('User not authenticated');
      return;
    }

    String getFileExtension(File file) {
      return file.path.split('.').last;
    }

    String getFileNameWithExtension(File file, String baseName) {
      return '$baseName.${getFileExtension(file)}';
    }

    try {
      final String propertyId = FirebaseFirestore.instance
          .collection('properties')
          .doc()
          .id;
      final storageRef = FirebaseStorage.instance.ref();

      
      String? propertyFrontUrl;
      if (_propertyFrontImage != null) {
        final frontRef = storageRef.child(
          'property_verification/${currentUser.uid}/$propertyId/${getFileNameWithExtension(_propertyFrontImage!, 'property_front')}',
        );
        await frontRef.putFile(_propertyFrontImage!);
        propertyFrontUrl = await frontRef.getDownloadURL();
      }

      
      String? businessPermitUrl;
      if (_businessPermitImage != null) {
        final businessRef = storageRef.child(
          'property_verification/${currentUser.uid}/$propertyId/${getFileNameWithExtension(_businessPermitImage!, 'business_permit')}',
        );
        await businessRef.putFile(_businessPermitImage!);
        businessPermitUrl = await businessRef.getDownloadURL();
      }

      
      String? validIdFrontUrl;
      if (_validIdFrontImage != null) {
        final idFrontRef = storageRef.child(
          'property_verification/${currentUser.uid}/$propertyId/${getFileNameWithExtension(_validIdFrontImage!, 'valid_id_front')}',
        );
        await idFrontRef.putFile(_validIdFrontImage!);
        validIdFrontUrl = await idFrontRef.getDownloadURL();
      }

      
      String? validIdBackUrl;
      if (_validIdBackImage != null) {
        final idBackRef = storageRef.child(
          'property_verification/${currentUser.uid}/$propertyId/${getFileNameWithExtension(_validIdBackImage!, 'valid_id_back')}',
        );
        await idBackRef.putFile(_validIdBackImage!);
        validIdBackUrl = await idBackRef.getDownloadURL();
      }

      
      List<String> faceScanUrls = [];
      for (int i = 0; i < _capturedFaces.length; i++) {
        final faceRef = storageRef.child(
          'property_verification/${currentUser.uid}/$propertyId/face_$i.jpg',
        );
        await faceRef.putFile(_capturedFaces[i]);
        final url = await faceRef.getDownloadURL();
        faceScanUrls.add(url);
      }

      
      await FirebaseFirestore.instance
          .collection('properties')
          .doc(propertyId)
          .set({
            'ownerId': currentUser.uid,
            'name': _propertyNameController.text.trim(),
            'location': _selectedLocation != null
                ? GeoPoint(
                    _selectedLocation!.latitude,
                    _selectedLocation!.longitude,
                  )
                : null,
            'locationAddress': _locationAddress,
            'address':
                '$_selectedBarangay, $_selectedCity, $_selectedProvince, $_selectedRegion',
            'backgroundImageUrl': propertyFrontUrl ?? '',
            'status': 'pending',
            'verificationData': {
              'propertyFrontUrl': propertyFrontUrl,
              'businessPermitUrl': businessPermitUrl,
              'validIdFrontUrl': validIdFrontUrl,
              'validIdBackUrl': validIdBackUrl,
              'faceScanUrls': faceScanUrls,
              'submittedAt': FieldValue.serverTimestamp(),
            },
            'verificationSchedule': null,
            'dateVerified': null,
            'region': _selectedRegion,
            'province': _selectedProvince,
            'city': _selectedCity,
            'barangay': _selectedBarangay,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Property verification request submitted successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to submit verification: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Property Information',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Start by providing the basic details of your property.',
          style: TextStyle(fontSize: 15, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _propertyNameController,
          decoration: InputDecoration(
            labelText: 'Property Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
            prefixIcon: Icon(Iconsax.building_4),
            hintText: 'e.g., "Rume\'s Place"',
          ),
        ),
        const SizedBox(height: 20),

        
        const Text(
          'Property Photo',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildImagePicker(
          documentFile: _propertyFrontImage,
          onTap: _pickPropertyFrontImage,
          onRemove: () => setState(() => _propertyFrontImage = null),
          label: 'Upload a clear front-view photo of your property.',
          icon: Iconsax.camera,
        ),

        const SizedBox(height: 20),

        
        const Text(
          'Property Location',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showExpandedMap,
          child: Container(
            height: 180,
            width: 500,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[50],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_selectedLocation != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: AbsorbPointer(
                      child: GoogleMap(
                        mapType: MapType.hybrid,
                        initialCameraPosition: CameraPosition(
                          target: _selectedLocation!,
                          zoom: 17,
                        ),
                        markers: {
                          Marker(
                            markerId: const MarkerId('property'),
                            position: _selectedLocation!,
                          ),
                        },
                        zoomControlsEnabled: false,
                      ),
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    color: _selectedLocation != null
                        ? Colors.black.withOpacity(0.4)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Iconsax.map_1,
                          size: 40,
                          color: _selectedLocation != null
                              ? Colors.white
                              : Colors.blueAccent,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedLocation != null
                              ? 'Tap to Change Location'
                              : 'Set Property Location on Map',
                          style: TextStyle(
                            color: _selectedLocation != null
                                ? Colors.white
                                : Colors.black.withOpacity(0.6),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_locationAddress != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Iconsax.location, size: 18, color: Colors.blue[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationAddress!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        _buildNavigationButtons(),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload Documents',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Provide the necessary documents to verify your ownership.',
          style: TextStyle(fontSize: 15, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),

        
        const Text(
          'Business Permit',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildImagePicker(
          documentFile: _businessPermitImage,
          onTap: () => _pickDocument('business'),
          onRemove: () => setState(() => _businessPermitImage = null),
          label: 'Upload a photo of your business permit.',
          icon: Iconsax.document_text_1,
        ),
        const SizedBox(height: 20),

        
        const Text(
          'Valid ID (Front)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildImagePicker(
          documentFile: _validIdFrontImage,
          onTap: () => _pickDocument('id_front'),
          onRemove: () => setState(() => _validIdFrontImage = null),
          label: 'Upload the front of your valid ID.',
          icon: Iconsax.card,
        ),
        const SizedBox(height: 20),

        
        const Text(
          'Valid ID (Back)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildImagePicker(
          documentFile: _validIdBackImage,
          onTap: () => _pickDocument('id_back'),
          onRemove: () => setState(() => _validIdBackImage = null),
          label: 'Upload the back of your valid ID.',
          icon: Iconsax.card_pos,
        ),
        const SizedBox(height: 20),
        _buildNavigationButtons(),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Face Scan Verification',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'We need to verify your identity with a quick face scan.',
          style: TextStyle(fontSize: 15, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        if (_faceCaptureStep < 1) ...[
          SizedBox(
            height: 350,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child:
                  _cameraController != null &&
                      _cameraController!.value.isInitialized
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        CameraPreview(_cameraController!),
                        
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.8),
                              width: 4,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        Container(
                          width: 240,
                          height: 320,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(120),
                          ),
                        ),
                        if (_isProcessingFace)
                          const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              _faceInstruction,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  _faceDetectionTimer != null && _faceDetectionTimer!.isActive
                  ? _stopAutoFaceCapture
                  : _startAutoFaceCapture,
              icon: Icon(
                _faceDetectionTimer != null && _faceDetectionTimer!.isActive
                    ? Iconsax.pause
                    : Iconsax.scan_barcode,
              ),
              label: Text(
                _faceDetectionTimer != null && _faceDetectionTimer!.isActive
                    ? 'Scanning...'
                    : 'Start Scan',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor:
                    _faceDetectionTimer != null && _faceDetectionTimer!.isActive
                    ? Colors.orange
                    : AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ] else ...[
          const Center(
            child: Icon(Iconsax.tick_circle, size: 100, color: Colors.green),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Face Scan Complete!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_capturedFaces.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                _capturedFaces.first,
                height: 250,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
        ],
        const SizedBox(height: 20),
        _buildNavigationButtons(),
      ],
    );
  }

  Widget _buildStep4() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadAddressData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final addressData = snapshot.data!;
        final regions = [addressData["region"]];
        final provinces = _selectedRegion != null
            ? [addressData["province"]]
            : [];
        final cities = _selectedProvince != null
            ? (addressData["cities"] as List)
                  .map((c) => c["name"] as String)
                  .toList()
            : [];
        final barangays = _selectedCity != null
            ? (addressData["cities"] as List)
                  .firstWhere((c) => c["name"] == _selectedCity)["barangays"]
                  .cast<String>()
            : [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Property Address',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Finally, specify the official address of your property.',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            _buildDropdown(
              label: 'Region',
              icon: Iconsax.map_1,
              value: _selectedRegion,
              items: regions.cast<String>(),
              onChanged: (val) => setState(() {
                _selectedRegion = val;
                _selectedProvince = null;
                _selectedCity = null;
                _selectedBarangay = null;
              }),
            ),
            const SizedBox(height: 16),
            _buildDropdown(
              label: 'Province',
              icon: Iconsax.map,
              value: _selectedProvince,
              items: provinces.cast<String>(),
              onChanged: _selectedRegion == null
                  ? null
                  : (val) => setState(() {
                      _selectedProvince = val;
                      _selectedCity = null;
                      _selectedBarangay = null;
                    }),
            ),
            const SizedBox(height: 16),
            _buildDropdown(
              label: 'City',
              icon: Iconsax.buildings,
              value: _selectedCity,
              items: cities.cast<String>(),
              onChanged: _selectedProvince == null
                  ? null
                  : (val) => setState(() {
                      _selectedCity = val;
                      _selectedBarangay = null;
                    }),
            ),
            const SizedBox(height: 16),
            _buildDropdown(
              label: 'Barangay',
              icon: Iconsax.building_3,
              value: _selectedBarangay,
              items: barangays.cast<String>(),
              onChanged: _selectedCity == null
                  ? null
                  : (val) => setState(() => _selectedBarangay = val),
            ),
            const SizedBox(height: 24),
            if (_selectedBarangay != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Iconsax.location_tick,
                      size: 24,
                      color: Colors.green[800],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Complete Address',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[900],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$_selectedBarangay, $_selectedCity, $_selectedProvince, $_selectedRegion',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.green[900],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            _buildNavigationButtons(),
          ],
        );
      },
    );
  }

  Widget _buildImagePicker({
    required File? documentFile,
    required VoidCallback onTap,
    required VoidCallback onRemove,
    required String label,
    required IconData icon,
  }) {
    IconData getFileIcon(String path) {
      final extension = path.split('.').last.toLowerCase();
      switch (extension) {
        case 'pdf':
          return Icons.picture_as_pdf;
        case 'doc':
        case 'docx':
          return Icons.description;
        default:
          return Icons.insert_drive_file;
      }
    }

    bool isImage(String path) {
      final extension = path.split('.').last.toLowerCase();
      return ['jpg', 'jpeg', 'png'].contains(extension);
    }

    return documentFile != null
        ? Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 180,
                  width: double.infinity,
                  color: Colors.grey[100],
                  child: isImage(documentFile.path)
                      ? Image.file(documentFile, fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              getFileIcon(documentFile.path),
                              size: 50,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                documentFile.path.split('/').last,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: CircleAvatar(
                  backgroundColor: Colors.black.withOpacity(0.6),
                  radius: 16,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                    onPressed: onRemove,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          )
        : GestureDetector(
            onTap: onTap,
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 36, color: AppColors.primary),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
  }

  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      value: value,
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _propertyNameController.text.isNotEmpty &&
            _selectedLocation != null &&
            _propertyFrontImage != null;
      case 1:
        return _businessPermitImage != null &&
            _validIdFrontImage != null &&
            _validIdBackImage != null;
      case 2:
        return _capturedFaces.length >= 1;
      case 3:
        return _selectedBarangay != null;
      default:
        return false;
    }
  }

  Widget _buildNavigationButtons() {
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            SizedBox(
              width: 120,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _currentStep--;
                  });
                },
                child: const Text('Previous'),
              ),
            )
          else
            const SizedBox(width: 120), 
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: _canProceed()
                  ? () {
                      if (_currentStep < 3) {
                        setState(() {
                          _currentStep++;
                        });
                      } else {
                        _submitVerificationRequest();
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: _isLoading && _currentStep == 3
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(_currentStep < 3 ? 'Next' : 'Submit'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_currentStep == 0) _buildStep1(),
          if (_currentStep == 1) _buildStep2(),
          if (_currentStep == 2) _buildStep3(),
          if (_currentStep == 3) _buildStep4(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Property Verification',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blueAccent,

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            color: Colors.blueAccent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStepIndicator(
                  icon: Iconsax.building_4,
                  label: 'Property',
                  stepIndex: 0,
                ),
                _buildStepDivider(),
                _buildStepIndicator(
                  icon: Iconsax.document_text_1,
                  label: 'Documents',
                  stepIndex: 1,
                ),
                _buildStepDivider(),
                _buildStepIndicator(
                  icon: Iconsax.scan_barcode,
                  label: 'Face Scan',
                  stepIndex: 2,
                ),
                _buildStepDivider(),
                _buildStepIndicator(
                  icon: Iconsax.map_1,
                  label: 'Address',
                  stepIndex: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildStepIndicator({
    required IconData icon,
    required String label,
    required int stepIndex,
  }) {
    final bool isCompleted = stepIndex < _currentStep;
    final bool isActive = stepIndex == _currentStep;

    final Color activeColor = Colors.white;
    final Color inactiveColor = Colors.white.withOpacity(0.6);
    final Color completedColor = Colors.lightGreenAccent;

    Color iconColor;
    Color labelColor;
    FontWeight labelWeight;

    if (isActive) {
      iconColor = activeColor;
      labelColor = activeColor;
      labelWeight = FontWeight.bold;
    } else if (isCompleted) {
      iconColor = completedColor;
      labelColor = completedColor;
      labelWeight = FontWeight.w500;
    } else {
      iconColor = inactiveColor;
      labelColor = inactiveColor;
      labelWeight = FontWeight.normal;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? Colors.white.withOpacity(0.2)
                : Colors.transparent,
            border: isActive ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Icon(
            isCompleted ? Iconsax.tick_circle : icon,
            color: iconColor,
            size: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontWeight: labelWeight,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider() {
    return Expanded(
      child: Divider(color: Colors.white.withOpacity(0.3), thickness: 1.5),
    );
  }
}
