import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:intl/intl.dart';
import 'package:iconsax/iconsax.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/components/currency.dart';
import 'package:screenshot/screenshot.dart';

class TransactionReceiptPage extends StatefulWidget {
  final Map<String, dynamic> transactionData;

  const TransactionReceiptPage({super.key, required this.transactionData});

  @override
  State<TransactionReceiptPage> createState() => _TransactionReceiptPageState();
}

class _TransactionReceiptPageState extends State<TransactionReceiptPage> {
  late Future<String> _relatedPartyNameFuture;
  late bool _isOwnerView;
  late String _relatedPartyRole;
  late Future<String> _propertyNameFuture;
  late Future<String> _roomNameFuture;
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _initializeRelatedParty();
    final tx = widget.transactionData;
    final propertyId = tx['propertyId'] as String?;
    _propertyNameFuture = _fetchDocField('properties', propertyId, 'name');
    _roomNameFuture = _fetchDocField(
      'properties/$propertyId/rooms',
      tx['roomId'] as String?,
      'name',
    );
  }

  void _initializeRelatedParty() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final tx = widget.transactionData;
    final ownerId = tx['ownerId'] as String?;
    final seekerId = tx['userId'] as String?; 
    final originalPayerId = tx['originalPayerId'] as String?; 

    
    if (tx['paymentType'] == 'commission') {
      _isOwnerView = true; 
      _relatedPartyRole = 'Original Payer';
      _relatedPartyNameFuture = _fetchUserName(originalPayerId);
      return;
    }

    
    if (currentUser?.uid == ownerId) {
      
      _isOwnerView = true;
      _relatedPartyRole = 'Payer Name';
      _relatedPartyNameFuture = _fetchUserName(seekerId);
    } else {
      
      _isOwnerView = false;
      _relatedPartyRole = 'Owner Name';
      _relatedPartyNameFuture = _fetchUserName(ownerId);
    }
  }

  Future<String> _fetchUserName(String? userId) async {
    if (userId == null) return 'N/A';
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        return '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
      }
      return 'User not found';
    } catch (e) {
      debugPrint('Error fetching user name: $e');
      return 'Error';
    }
  }

  Future<String> _fetchDocField(
    String collectionPath,
    String? docId,
    String fieldName,
  ) async {
    if (docId == null) return 'N/A';
    try {
      final ownerDoc = await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(docId)
          .get();
      if (ownerDoc.exists) {
        final data = ownerDoc.data()!;
        return data[fieldName] ?? 'Not Found';
      }
      return 'Not Found';
    } catch (e) {
      debugPrint('Error fetching $fieldName: $e');
      return 'Error';
    }
  }

  String _getPaymentMethodAsset(String? method) {
    switch (method?.toLowerCase()) {
      case 'gcash':
        return 'assets/payments/GCash.png';
      case 'paymaya':
        return 'assets/payments/Paymaya.png';
      case 'grab_pay':
        return 'assets/payments/Grabpay.png';
      default:
        
        return 'assets/payments/Paymaya.png';
    }
  }

  Future<void> _downloadReceipt() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    try {
      
      PermissionStatus status;
      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          
          status = await Permission.photos.request();
        } else {
          status = await Permission.storage.request();
        }
      } else {
        status = await Permission.photos.request(); 
      }

      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Storage permission is required to save the receipt.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return; 
      }

      
      final Uint8List? image = await _screenshotController.capture(
        delay: const Duration(milliseconds: 10),
      );
      if (image == null) throw Exception("Failed to capture receipt.");

      
      final result = await ImageGallerySaverPlus.saveImage(
        image,
        name:
            "receipt_${widget.transactionData['transactionId'] ?? DateTime.now().millisecondsSinceEpoch}",
      );

      if (mounted && result['isSuccess']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt saved to gallery!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(result['errorMessage'] ?? "Failed to save image.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transactionData;
    final paymentType = tx['paymentType'] ?? 'Payment';
    String description;
    switch (paymentType) {
      case 'booking':
        description = 'Booking Fee Payment';
        break;
      case 'final_payment':
        description = 'Final Rent Settlement';
        break;
      default: 
        description = 'Monthly Rent Payment';
    }
    final transactionId = tx['transactionId'] ?? 'N/A';
    final paymentMethod = tx['method'] ?? 'N/A';

    
    final int baseAmount = _isOwnerView
        ? (tx['netAmount'] ?? 0)
        : (tx['amount'] ?? 0);
    final int rumeFee = tx['rumeServiceFee'] ?? 0;
    final int gatewayFee = tx['paymongoFee'] ?? 0;
    
    final int totalAmountPaidBySeeker =
        tx['totalAmount'] ?? (baseAmount + rumeFee + gatewayFee);

    final date = (tx['createdAt'] is Timestamp)
        ? (tx['createdAt'] as Timestamp).toDate()
        : null;

    final String paymentLogoAsset = _getPaymentMethodAsset(paymentMethod);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Transaction Receipt',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              onPressed: _isDownloading ? null : _downloadReceipt,
              tooltip: 'Download Receipt',
              icon: _isDownloading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(
                      Iconsax.document_download,
                      color: Colors.black54,
                    ),
            ),
          ),
        ],
      ),
      body: Screenshot(
        controller: _screenshotController,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(totalAmountPaidBySeeker, date),
                    const Divider(height: 28, thickness: 1),
                    _buildSectionHeader("Transaction Summary"),
                    const SizedBox(height: 12),
                    _buildDetailRow('Transaction ID', transactionId),
                    _buildDetailRow('Description', description),
                    _buildDetailRow(
                      'Payment Method',
                      paymentMethod.toString().toUpperCase(),
                    ),
                    FutureBuilder<String>(
                      future: _propertyNameFuture,
                      builder: (context, snapshot) {
                        return _buildDetailRow(
                          'Property Name',
                          snapshot.data ?? 'Loading...',
                        );
                      },
                    ),
                    FutureBuilder<String>(
                      future: _roomNameFuture,
                      builder: (context, snapshot) {
                        return _buildDetailRow(
                          'Room Name',
                          snapshot.data ?? 'Loading...',
                        );
                      },
                    ),
                    const Divider(height: 32, thickness: 1),
                    
                    _isOwnerView
                        ? _buildOwnerPaymentBreakdown(tx)
                        : _buildSeekerPaymentBreakdown(tx),
                    const Divider(height: 32, thickness: 1),
                    FutureBuilder<String>(
                      future: _relatedPartyNameFuture,
                      builder: (context, snapshot) {
                        return _buildDetailRow(
                          _relatedPartyRole,
                          snapshot.data ?? 'Loading...',
                        );
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      paymentLogoAsset,
                      width: 50,
                      height: 50,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Iconsax.wallet, size: 30),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeekerPaymentBreakdown(Map<String, dynamic> tx) {
    final paymentType = tx['paymentType'] ?? 'rent';
    final int baseAmount = tx['amount'] ?? 0;
    final int rumeFee = tx['rumeServiceFee'] ?? 0;
    final int gatewayFee = tx['paymongoFee'] ?? 0;
    final int totalAmount =
        tx['totalAmount'] ?? (baseAmount + rumeFee + gatewayFee);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Payment Breakdown',
          
          
          
          
          
        ),
        const SizedBox(height: 12),
        _buildPriceRow(
          paymentType == 'booking'
              ? 'Pro-rated Room Price'
              : (paymentType == 'final_payment'
                    ? 'Outstanding Balance'
                    : 'Monthly Rent'),
          baseAmount.toDouble(),
        ),
        _buildPriceRow('RuMe Service Fee', rumeFee.toDouble()),
        _buildPriceRow('Payment Gateway Fee', gatewayFee.toDouble()),
        const Divider(height: 24),
        _buildPriceRow(
          'Total Amount Paid',
          totalAmount.toDouble(),
          isTotal: true,
        ),
      ],
    );
  }

  Widget _buildOwnerPaymentBreakdown(Map<String, dynamic> tx) {
    final int netAmount = tx['netAmount'] ?? 0;
    final int rumeFee =
        tx['commission'] ?? 0; 
    final int gatewayFee = tx['paymongoFee'] ?? 0;
    final int grossAmount = netAmount + rumeFee + gatewayFee;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Earnings Breakdown'),
        const SizedBox(height: 12),
        _buildPriceRow('Gross Payment', grossAmount.toDouble()),
        _buildPriceRow('RuMe Service Fee', -rumeFee.toDouble(), isFee: true),
        _buildPriceRow(
          'Payment Gateway Fee',
          -gatewayFee.toDouble(),
          isFee: true,
        ),
        const Divider(height: 24),
        _buildPriceRow(
          'Net Amount Received',
          netAmount.toDouble(),
          isTotal: true,
          totalColor: AppColors.successGreen,
        ),
      ],
    );
  }

  Widget _buildHeader(int totalAmount, DateTime? date) {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.successGreen, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Iconsax.tick_circle,
              color: Colors.white,
              size: 42,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Payment Successful',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currencyFormatter.format(totalAmount / 100),
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              fontFamily: 'Roboto',
              color: Colors.black,
            ),
          ),
          if (date != null)
            Text(
              DateFormat('MMMM d, yyyy \'at\' h:mm a').format(date),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontFamily: 'Poppins',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
          letterSpacing: 0.5,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(
    String label,
    double amount, {
    bool isTotal = false,
    bool isFee = false,
    Color? totalColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isTotal
                  ? Colors.black
                  : (isFee ? Colors.red[700] : Colors.grey[700]),
              fontFamily: 'Poppins',
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${isFee ? '-' : ''}${currencyFormatter.format(amount.abs() / 100)}',
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Roboto',
              color: isFee ? Colors.red[700] : (isTotal ? totalColor : null),
            ),
          ),
        ],
      ),
    );
  }
}
