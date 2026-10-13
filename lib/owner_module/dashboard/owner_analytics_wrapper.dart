
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rume/components/loading_screen.dart';
import 'package:rume/owner_module/dashboard/analytics_page.dart';
import 'package:rume/components/app_colors.dart';

class OwnerAnalyticsWrapper extends StatefulWidget {
  const OwnerAnalyticsWrapper({super.key});

  @override
  State<OwnerAnalyticsWrapper> createState() => _OwnerAnalyticsWrapperState();
}

class _OwnerAnalyticsWrapperState extends State<OwnerAnalyticsWrapper> {
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isLoading = true;
  String? _selectedPropertyId;
  String _selectedPropertyName = 'Property';
  List<DocumentSnapshot> _verifiedProperties = [];
  int _currentPropertyIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    await Future.delayed(const Duration(milliseconds: 800));

    if (_user != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('properties')
          .where('ownerId', isEqualTo: _user.uid)
          .where('status', isEqualTo: 'verified')
          .orderBy('createdAt', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        _verifiedProperties = snapshot.docs;
        final property = snapshot.docs[_currentPropertyIndex];
        setState(() {
          _selectedPropertyId = property.id;
          _selectedPropertyName = property.get('name') ?? 'Property';
        });
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showPropertySwitcher() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600, maxWidth: 500),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.swap_horiz,
                    color: AppColors.blue900,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Switch Property',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.blue900,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _verifiedProperties.length,
                  itemBuilder: (context, index) {
                    final property = _verifiedProperties[index];
                    final propertyData =
                        property.data() as Map<String, dynamic>;
                    final propertyName =
                        propertyData['name'] ?? 'Unnamed Property';
                    final isSelected = index == _currentPropertyIndex;

                    return Card(
                      elevation: isSelected ? 4 : 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.blue900
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            _currentPropertyIndex = index;
                            _selectedPropertyId = property.id;
                            _selectedPropertyName = propertyName;
                          });
                          Navigator.pop(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.blue900.withOpacity(0.1)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.home_work,
                                  color: isSelected
                                      ? AppColors.blue900
                                      : Colors.grey[600],
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      propertyName,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? AppColors.blue900
                                            : Colors.black87,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      propertyData['address'] ?? 'No address',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.blue900,
                                  size: 28,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const StandardLoadingScreen();
    }

    if (_selectedPropertyId == null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: const Text(
            'Analytics',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bar_chart_outlined,
                  size: 100,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 24),
                const Text(
                  'No Verified Properties',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Add and verify your first property to view analytics',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Column(
          children: [
            const Text(
              'Analytics',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          
            Text(
              _selectedPropertyName,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (_verifiedProperties.length > 1)
            IconButton(
              icon: const Icon(
                Icons.swap_horiz,
                color: AppColors.blue900,
                size: 28,
              ),
              onPressed: _showPropertySwitcher,
              tooltip: 'Switch Property',
            ),
        ],
      ),
      body: AnalyticsPage(
        key: ValueKey(_selectedPropertyId),
        propertyId: _selectedPropertyId!,
        propertyName: _selectedPropertyName,
        ownerId: _user!.uid,
      ),
    );
  }
}