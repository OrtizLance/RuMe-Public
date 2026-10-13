import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rume/components/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:rume/components/currency.dart';
import 'package:rume/components/loading_screen.dart';
import 'package:rume/owner_module/payments/withdrawal_history_page.dart';
import 'package:rume/owner_module/payments/withdrawal_page.dart';

import 'package:rume/seeker_module/booking_payment/transaction_receipt_page.dart';

class OwnerWalletPage extends StatefulWidget {
  const OwnerWalletPage({super.key});

  @override
  State<OwnerWalletPage> createState() => _OwnerWalletPageState();
}

class _OwnerWalletPageState extends State<OwnerWalletPage> {
  bool _isLoading = true;
  String? _selectedPropertyIdFilter;

  @override
  void initState() {
    super.initState();
    _loadDataWithDelay();
  }

  Future<void> _loadDataWithDelay() async {
    
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: Text(
            "My Wallet",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: const Center(child: Text('Please log in to view your wallet')),
      );
    }

    final walletRef = FirebaseFirestore.instance
        .collection('wallets')
        .doc(currentUser.uid);

    return StreamBuilder<DocumentSnapshot>(
      stream: walletRef.snapshots(),
      builder: (context, snapshot) {
        
        if (_isLoading ||
            (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData)) {
          return const StandardLoadingScreen();
        }

        
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            title: Text(
              "My Wallet",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: SafeArea(
            child: Builder(
              builder: (context) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Error loading wallet",
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No wallet found",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Your wallet will be created automatically when you receive your first payment",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final wallet = snapshot.data!.data() as Map<String, dynamic>;
                final balance = (wallet['amount'] ?? 0) / 100;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBalanceCard(context, balance, walletRef),
                      const SizedBox(height: 24),
                      Text(
                        "Transactions",
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.blue900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTransactionsList(walletRef),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildBalanceCard(
    BuildContext context,
    double balance,
    DocumentReference walletRef,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment.centerLeft,
          radius: 2.0,
          colors: [Color(0xFF4FC3F7), Color(0xFF1565C0), Color(0xFF0D47A1)],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Current Balance",
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            currencyFormatter.format(balance),
            style: const TextStyle(
              fontFamily: 'Roboto',
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(color: Colors.white24, height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WithdrawalPage(currentBalance: balance),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send_to_mobile, size: 20),
                  label: const Text('Withdraw'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WithdrawalHistoryPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history, size: 20),
                  label: const Text('History'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          _buildPropertyBreakdown(context, walletRef),
        ],
      ),
    );
  }

  Widget _buildTransactionsList(DocumentReference walletRef) {
    return StreamBuilder<QuerySnapshot>(
      stream: walletRef
          .collection('transactions')
          .where(_selectedPropertyIdFilter == null
              ? 'createdAt'
              : 'propertyId', isEqualTo: _selectedPropertyIdFilter)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, txSnapshot) {
        if (txSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (txSnapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 8),
                  Text(
                    "Error loading transactions",
                    style: TextStyle(
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!txSnapshot.hasData || txSnapshot.data!.docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "No transactions yet",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Transactions will appear here",
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }

        final transactions = txSnapshot.data!.docs;

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: transactions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final tx = transactions[index].data() as Map<String, dynamic>;
            return _buildTransactionItem(tx);
          },
        );
      },
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final netAmount = (tx['netAmount'] ?? 0) / 100;
    final commission = (tx['commission'] ?? 0) / 100;
    final paymongoFee = (tx['paymongoFee'] ?? 0) / 100;
    final grossAmount = netAmount + commission + paymongoFee;

    final paymentType = tx['paymentType'] ?? 'payment';
    final payer = tx['payerName'] ?? "Unknown";

    final date = (tx['createdAt'] is Timestamp)
        ? (tx['createdAt'] as Timestamp).toDate()
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.onSurfaceGray),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Builder(
        builder: (context) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TransactionReceiptPage(transactionData: tx),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          paymentType == 'booking'
                              ? 'Booking Payment'
                              : 'Rent Payment',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D47A1),
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          currencyFormatter.format(netAmount),
                          style: const TextStyle(
                            color: AppColors.successGreen,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "From: $payer",
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Gross Amount",
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        Text(
                          currencyFormatter.format(grossAmount),
                          style: const TextStyle(fontFamily: 'Roboto'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "RuMe Service Fee",
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        Text(
                          "- ${currencyFormatter.format(commission)}",
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Payment Gateway Fee",
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        Text(
                          "- ${currencyFormatter.format(paymongoFee)}",
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (date != null)
                      Text(
                        DateFormat('MMMM d, yyyy \'at\' h:mm a').format(date),
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPropertyBreakdown(
      BuildContext context, DocumentReference walletRef) {
    return StreamBuilder<QuerySnapshot>(
      stream: walletRef.collection('transactions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final transactions = snapshot.data!.docs;
        final Map<String, double> propertyEarnings = {};

        for (var txDoc in transactions) {
          final tx = txDoc.data() as Map<String, dynamic>;
          final propertyId = tx['propertyId'] as String?;
          final netAmount = (tx['netAmount'] ?? 0).toDouble();

          if (propertyId != null) {
            propertyEarnings.update(
              propertyId,
              (value) => value + netAmount,
              ifAbsent: () => netAmount,
            );
          }
        }

        if (propertyEarnings.isEmpty) {
          return const Text(
            'No property-specific earnings yet.',
            style: TextStyle(color: Colors.white70),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedPropertyIdFilter != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedPropertyIdFilter = null;
                      });
                    },
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear Filter'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ...propertyEarnings.entries.map((entry) {
                final isSelected = _selectedPropertyIdFilter == entry.key;
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('properties')
                      .doc(entry.key)
                      .get(),
                  builder: (context, propSnapshot) {
                    final propertyName = (propSnapshot.data?.data()
                            as Map<String, dynamic>?)?['name'] ??
                        'Unknown Property';
                    final amount = entry.value / 100;

                    return Material(
                      color: isSelected
                          ? Colors.white.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedPropertyIdFilter = null;
                            } else {
                              _selectedPropertyIdFilter = entry.key;
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8.0, horizontal: 12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                propertyName,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              Text(
                                currencyFormatter.format(amount),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}
