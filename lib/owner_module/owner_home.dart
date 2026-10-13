
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';


const Color primaryIndigo = Color(0xFF3F51B5);
const Color backgroundWhite = Color.fromARGB(255, 255, 255, 255);
const Color textGray = Color.fromARGB(255, 148, 147, 147);

class OwnerHome extends StatelessWidget {
  final Widget child;
  const OwnerHome({required this.child, super.key});

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/owner-dashboard')) return 0;
    if (location.startsWith('/owner-listings')) return 1;
    if (location.startsWith('/owner-transactions')) return 2;
    if (location.startsWith('/owner-analytics')) return 3;
    if (location.startsWith('/owner-profile')) return 4;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/owner-dashboard');
        break;
      case 1:
        context.go('/owner-listings');
        break;
      case 2:
        context.go('/owner-transactions');
        break;
      case 3:
        context.go('/owner-analytics');
        break;
      case 4:
        context.go('/owner-profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
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
            backgroundColor: backgroundWhite,
            elevation: 0,
            selectedItemColor: primaryIndigo,
            unselectedItemColor: textGray,
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
                icon: Icon(Iconsax.task_square, size: 26),
                activeIcon: Icon(Iconsax.task, size: 26),
                label: 'Listings',
              ),
              BottomNavigationBarItem(
                icon: Icon(Iconsax.wallet_3, size: 26),
                activeIcon: Icon(Iconsax.wallet_check, size: 26),
                label: 'Payments',
              ),
              BottomNavigationBarItem(
                icon: Icon(Iconsax.chart_2, size: 26),
                activeIcon: Icon(Iconsax.chart, size: 26),
                label: 'Analytics',
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