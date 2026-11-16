import 'package:flutter/material.dart';

class TechSidebar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const TechSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  State<TechSidebar> createState() => _TechSidebarState();
}

class _TechSidebarState extends State<TechSidebar> {
  int? hoveredIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: const Color(0xFF0B1220),
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "COLLEGE BELL",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(height: 40),
          _buildItem(Icons.dashboard, "Dashboard", 0),
          const SizedBox(height: 10),
          _buildItem(Icons.apartment, "Departments", 1),
          const Spacer(),
          _buildItem(Icons.logout, "Logout", 2),
        ],
      ),
    );
  }

  Widget _buildItem(IconData icon, String label, int index) {
    final isSelected = widget.selectedIndex == index;
    final isHovered = hoveredIndex == index;

    return MouseRegion(
      onEnter: (_) => setState(() => hoveredIndex = index),
      onExit: (_) => setState(() => hoveredIndex = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onItemSelected(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF111827)
                : isHovered
                    ? const Color(0xFF111827).withOpacity(0.6)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFF00E5FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                icon,
                color: isSelected || isHovered
                    ? const Color(0xFF00E5FF)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isSelected || isHovered
                      ? const Color(0xFFE5E7EB)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
