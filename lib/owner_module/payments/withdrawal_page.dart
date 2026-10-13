import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:rume/components/app_colors.dart';
import 'package:rume/components/currency.dart';

class WithdrawalPage extends StatefulWidget {
  final double currentBalance;

  const WithdrawalPage({super.key, required this.currentBalance});

  @override
  State<WithdrawalPage> createState() => _WithdrawalPageState();
}

class _WithdrawalPageState extends State<WithdrawalPage> {
  
  final _pageController = PageController();
  int _pageIndex = 0;
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();

  
  double _amountToWithdraw = 0.0;
  double _serviceFee = 0.0;
  double _netAmount = 0.0;

  
  final _amountController = TextEditingController();

  
  String? _selectedMethod;
  bool _isProcessing = false;

  
  final List<String> _eWalletMethods = ['GCash', 'PayMaya', 'GrabPay'];
  final List<String> _bankMethods = ['Bank Transfer'];

  @override
  void dispose() {
    _pageController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _nextPage() {
    bool isValid = false;
    if (_pageIndex == 0) {
      isValid = _step1FormKey.currentState?.validate() ?? false;
    } else if (_pageIndex == 1) {
      if (_step2FormKey.currentState!.validate()) {
        
        final amount = double.tryParse(_amountController.text) ?? 0.0;
        setState(() {
          _amountToWithdraw = amount;
          _serviceFee = amount * 0.05;
          _netAmount = amount - (amount * 0.05);
        });
        isValid = true; 
      }
    }

    if (isValid) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    }
  }

  void _previousPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _submitWithdrawalRequest() async {
    
    if (_selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a withdrawal method.')),
      );
      _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      setState(() => _pageIndex = 0); 
      return;
    }
    final isStep2Valid = _step2FormKey.currentState?.validate() ?? false;

    if (!isStep2Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a valid amount to withdraw.')),
      );
      _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      setState(() => _pageIndex = 1); 
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Withdrawal amount cannot exceed your current balance.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('requestWithdrawal');
      final result = await callable.call<Map<String, dynamic>>({
        'amount': (amount * 100).round(), 
        'method': _selectedMethod,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.data['message'] ?? 'Request submitted!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); 
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Request Withdrawal'),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1(),
                  _buildStep2(),
                  _buildStep3(),
                ],
              ),
            ),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEP ${_pageIndex + 1} OF 3',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.blue700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: _pageIndex >= index
                        ? AppColors.primaryColor
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primaryColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[400]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[400]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding:
          const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Form(
        key: _step1FormKey,
        child: Column( 
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Select Method',
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2F4D)),
              textAlign: TextAlign.center,
            ),
            Text(
              "Choose where you'd like to send the funds.",
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            Image.asset(
              'assets/images/Sign_add.png',
              height: 240,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: _selectedMethod,
              decoration:
                  _inputDecoration('Withdrawal Method', Icons.account_balance_wallet_outlined),
              items: [..._eWalletMethods, ..._bankMethods].map((String method) {
                return DropdownMenuItem<String>(
                  value: method,
                  child: Text(method),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedMethod = newValue!;
                });
              },
              validator: (value) =>
                  value == null ? 'Please select a method' : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Form(
        key: _step2FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter Details',
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2F4D)),
              textAlign: TextAlign.center,
            ),
            Text(
              "Specify the amount and your account.",
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  Text('Available Balance',
                      style: TextStyle(color: Colors.blue[800], fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(currencyFormatter.format(widget.currentBalance),
                      style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Roboto')),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  _inputDecoration('Amount to Withdraw', Icons.money_outlined),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter an amount.';
                }
                final amount = double.tryParse(value);
                if (amount == null || amount <= 0) {
                  return 'Please enter a valid amount.';
                }
                if (amount > widget.currentBalance) {
                  return 'Amount exceeds available balance.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confirm & Withdraw',
            style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2F4D)),
            textAlign: TextAlign.center,
          ),
          Text(
            "Review the details before you confirm.",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          Image.asset(
            'assets/images/Sign_cre.png',
            height: 180,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Colors.grey[100],
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildBreakdownRow('Amount to Withdraw:',
                      currencyFormatter.format(_amountToWithdraw)),
                  const SizedBox(height: 8),
                  _buildBreakdownRow('Service Fee (5%):',
                      '- ${currencyFormatter.format(_serviceFee)}',
                      isFee: true),
                  const Divider(height: 24),
                  _buildBreakdownRow('You Will Receive:',
                      currencyFormatter.format(_netAmount),
                      isTotal: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green[800]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Withdrawals are processed instantly. The funds will be transferred to your selected account.', 
                    style: TextStyle(color: Colors.green[800]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Row(
        children: [
          if (_pageIndex > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _previousPage,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: Colors.grey[400]!),
                ),
                child: const Text('Back',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          if (_pageIndex > 0) const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _isProcessing
                  ? null
                  : (_pageIndex == 2 ? _submitWithdrawalRequest : _nextPage),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 5,
                shadowColor: AppColors.primaryColor.withOpacity(0.4),
              ),
              child: _isProcessing && _pageIndex == 2
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(
                      _pageIndex == 2 ? 'Confirm & Withdraw' : 'Next',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, String value,
      {bool isTotal = false, bool isFee = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: Colors.grey[700])),
        Text(value,
            style: TextStyle(
                fontSize: isTotal ? 18 : 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
                color: isFee
                    ? Colors.red
                    : (isTotal ? AppColors.blue900 : Colors.black87))),
      ],
    );
  }
}