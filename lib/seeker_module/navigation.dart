

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rume/components/app_colors.dart';
import 'package:iconsax/iconsax.dart';
class MainScreen extends StatefulWidget {
  final Widget child;
  const MainScreen({required this.child, super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  
  
  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/property-search')) return 1; 
    if (location.startsWith('/bookings')) return 2;
    if (location.startsWith('/checkout')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0; 
  }

  
  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/property-search');
        break;
      case 2:
        context.go('/bookings');
        break;
      case 3:
        context.go('/checkout');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      body: widget.child,
      backgroundColor: Colors.white,
      
      
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
          child: BottomNavigationBar(
            currentIndex: _calculateSelectedIndex(context),
            onTap: (index) => _onItemTapped(index, context),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.backgroundWhite,
            elevation: 0,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textGray,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
            ),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Iconsax.home, size: 26),
                activeIcon: Icon(Iconsax.home_2, size: 26),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Iconsax.search_normal, size: 26),
                activeIcon: Icon(Iconsax.search_favorite, size: 26),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Iconsax.document_text, size: 26),
                activeIcon: Icon(Iconsax.document_text_1, size: 26),
                label: 'Bookings',
              ),
              BottomNavigationBarItem(
                icon: Icon(Iconsax.wallet_3, size: 26),
                activeIcon: Icon(Iconsax.wallet_check, size: 26),
                label: 'Payments',
              ),
              BottomNavigationBarItem(
                icon: Icon(Iconsax.user, size: 26),
                activeIcon: Icon(Iconsax.user_octagon, size: 26),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
