import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/components/currency.dart';

class WithdrawalHistoryPage extends StatelessWidget {
  const WithdrawalHistoryPage({super.key});

  Widget _buildStatusChip(String status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'completed':
        color = Colors.green;
        label = 'Completed';
        icon = Icons.check_circle;
        break;
      case 'declined':
        color = Colors.red;
        label = 'Declined';
        icon = Icons.cancel;
        break;
      case 'pending':
      default:
        color = Colors.orange;
        label = 'Pending';
        icon = Icons.hourglass_empty;
        break;
    }

    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Withdrawal History')),
        body: const Center(child: Text('Please log in.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Withdrawal History'),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('withdrawals')
            .where('userId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint('Withdrawal History Error: ${snapshot.error}');
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No Withdrawals Yet',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your withdrawal requests will appear here.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index].data() as Map<String, dynamic>;
              final amount = (request['amount'] ?? 0) / 100.0;
              final status = request['status'] ?? 'pending';
              final date = (request['createdAt'] as Timestamp?)?.toDate();
              final method = request['method'] ?? 'N/A';
              final ownerName = request['userName'] ?? 'N/A';
              final accountNumber = request['accountNumber'] ?? 'N/A';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            currencyFormatter.format(amount),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Roboto',
                              color: AppColors.blue900,
                            ),
                          ),
                          _buildStatusChip(status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (date != null)
                        Text(
                          DateFormat('MMMM d, yyyy \'at\' h:mm a').format(date),
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      const Divider(height: 24),
                      _buildDetailRow(Icons.payment, 'Method', '$method'),
                      _buildDetailRow(Icons.person, 'Owner Name', ownerName),
                      _buildDetailRow(Icons.pin, 'Account Number', accountNumber),
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Colors.grey[700])),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}