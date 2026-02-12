import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenants.dart';
import 'totalroom.dart';
import 'availableroom.dart';
import '../services/room_service.dart';
import 'landlord_bottom_nav.dart'; // ✅ shared bottom nav

class Dashboard extends StatefulWidget {
  final bool showLoginSuccess; // 🔹 NEW FLAG

  const Dashboard({
    super.key,
    this.showLoginSuccess = false,
  });

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final RoomService _roomService = RoomService();
  late final Stream<List<Map<String, dynamic>>> _roomStream;

  // 🔹 Supabase client + tenant stream (real active tenants for this landlord)
  final _sb = Supabase.instance.client;
  late final Stream<List<Map<String, dynamic>>> _tenantStream;

  // 🔹 Ensure dialog is only shown once per dashboard instance
  bool _hasShownLoginDialog = false;

  @override
  void initState() {
    super.initState();

    _roomStream = _roomService.streamMyRooms();
    _tenantStream = _streamTenantsSafe();

    // 🔹 Show login success modal once after landing from Login
    if (widget.showLoginSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasShownLoginDialog) {
          _hasShownLoginDialog = true;
          _showLoginSuccessDialog();
        }
      });
    }
  }

  void _showLoginSuccessDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        // ✅ Auto-close after 1 second (no button)
        Future.delayed(const Duration(seconds: 1), () {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        });

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF10B981).withOpacity(0.12),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF10B981),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  "Login successful",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "You have successfully logged into your landlord dashboard.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.4,
                  ),
                ),
                // ✅ Removed the "Continue/Okay" button
              ],
            ),
          ),
        );
      },
    );
  }

  // 🔹 Same filtering logic as in Tenants page
  Stream<List<Map<String, dynamic>>> _streamTenantsSafe() {
    final me = _sb.auth.currentUser?.id;
    if (me == null) return const Stream.empty();

    return _sb.from('room_tenants').stream(primaryKey: ['id']).map((rows) {
      final list = List<Map<String, dynamic>>.from(rows);
      return list.where((t) {
        final status = (t['status'] ?? '').toString().toLowerCase();
        final ll = (t['landlord_id'] ?? '').toString();
        return status == 'active' && ll == me;
      }).toList();
    });
  }

  @override
  void dispose() {
    _roomService.dispose();
    super.dispose();
  }

  String _availability(Map<String, dynamic> r) {
    final a = (r['availability_status'] ?? '').toString().toLowerCase();
    if (a == 'available' || a == 'not_available') return a;
    final s = (r['status'] ?? '').toString().toLowerCase();
    return s == 'available' ? 'available' : 'not_available';
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryTop = Color(0xFF00324E);
    const Color primaryBottom = Color(0xFF005B96);
    const Color cardBg = Colors.white;
    const Color textPrimary = Color(0xFF111827);
    const Color textSecondary = Color(0xFF6B7280);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryTop, primaryBottom],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Color(0xFF04354B),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: const Text(
            "DASHBOARD",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 20,
              letterSpacing: 0.8,
            ),
          ),
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _roomStream,
          initialData: const [],
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load rooms:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            }

            final rooms = snapshot.data ?? const [];
            final int totalRooms = rooms.length;
            final int vacantRooms =
                rooms.where((r) => _availability(r) == 'available').length;
            final int occupiedRooms =
                rooms.where((r) => _availability(r) == 'not_available').length;

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- HEADER SUMMARY CARD ---
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.dashboard_customize_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Overview",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "You have $totalRooms rooms",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Vacant: $vacantRooms • Occupied: $occupiedRooms",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // --- METRICS CARDS ---
                    Row(
                      children: [
                        Expanded(
                          child: _buildDashboardCard(
                            number: totalRooms.toString(),
                            title: "Total Rooms",
                            icon: Icons.door_front_door,
                            bgColor: cardBg,
                            titleColor: textPrimary,
                            numberColor: const Color(0xFF2563EB),
                            chipText:
                                "Vacant $vacantRooms  |  Occ. $occupiedRooms",
                            onMoreInfo: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const TotalRoom(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDashboardCard(
                            number: vacantRooms.toString(),
                            title: "Vacant",
                            icon: Icons.meeting_room_outlined,
                            bgColor: cardBg,
                            titleColor: textPrimary,
                            numberColor: const Color(0xFF10B981),
                            chipText: "See available rooms",
                            onMoreInfo: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AvailableRoom(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        // 🔹 Tenants card now uses real active tenant count
                        Expanded(
                          child: StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _tenantStream,
                            initialData: const [],
                            builder: (context, tenantSnap) {
                              final tenants = tenantSnap.data ?? const [];
                              final tenantCount = tenants.length;

                              return _buildDashboardCard(
                                number: tenantCount.toString(),
                                title: "Tenants",
                                icon: Icons.group_outlined,
                                bgColor: cardBg,
                                titleColor: textPrimary,
                                numberColor: const Color(0xFFF97316),
                                chipText: "Manage tenants",
                                onMoreInfo: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const Tenants(),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDashboardCard(
                            number: occupiedRooms.toString(),
                            title: "Occupied",
                            icon: Icons.king_bed_outlined,
                            bgColor: cardBg,
                            titleColor: textPrimary,
                            // ✅ Occupied card icon/number color is this:
                            numberColor: const Color(0xFFEC4899),
                            chipText: "Currently occupied",
                            onMoreInfo: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const TotalRoom(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // --- ANALYTICS SECTION ---
                    const Text(
                      "Analytics",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Single wide Occupancy card with PIE chart
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Occupancy",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "Occupied vs Vacant rooms",
                            style: TextStyle(
                              fontSize: 11,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 180,
                            child: OccupancyPieChart(
                              occupied: occupiedRooms,
                              vacant: vacantRooms,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              _LegendDot(color: Color(0xFFEC4899)), // ✅ Occupied matches occupied card color
                              SizedBox(width: 4),
                              Text(
                                "Occupied",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textSecondary,
                                ),
                              ),
                              SizedBox(width: 16),
                              _LegendDot(color: Color(0xFF10B981)), // ✅ Vacant green
                              SizedBox(width: 4),
                              Text(
                                "Vacant",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    // 🔥 Recent Activity removed as requested
                  ],
                ),
              ),
            );
          },
        ),
        // ✅ Shared bottom nav: index 0 = Dashboard
        bottomNavigationBar: const LandlordBottomNav(
          currentIndex: 0,
        ),
      ),
    );
  }

  // Modern card with small chip + "More" button behavior
  Widget _buildDashboardCard({
    required String number,
    required String title,
    required IconData icon,
    required Color bgColor,
    required Color titleColor,
    required Color numberColor,
    String? chipText,
    VoidCallback? onMoreInfo,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: numberColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: numberColor, size: 18),
              ),
              const Spacer(),
              Text(
                number,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: numberColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: titleColor,
            ),
          ),
          if (chipText != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                chipText,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (onMoreInfo != null)
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onMoreInfo,
                icon: Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: numberColor,
                ),
                label: Text(
                  "View details",
                  style: TextStyle(
                    fontSize: 12,
                    color: numberColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ✅ Pie chart for Occupancy (occupied matches occupied card color, vacant = green)
class OccupancyPieChart extends StatelessWidget {
  final int occupied;
  final int vacant;

  const OccupancyPieChart({
    super.key,
    required this.occupied,
    required this.vacant,
  });

  @override
  Widget build(BuildContext context) {
    final total = occupied + vacant;
    // Avoid all-zero weirdness
    final double occupiedValue = total == 0 ? 1 : occupied.toDouble();
    final double vacantValue = total == 0 ? 1 : vacant.toDouble();

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 26,
        sections: [
          PieChartSectionData(
            color: const Color(0xFFEC4899), // ✅ Occupied matches occupied card color
            value: occupiedValue,
            title: '',
            radius: 42,
          ),
          PieChartSectionData(
            color: const Color(0xFF10B981), // ✅ Vacant - green
            value: vacantValue,
            title: '',
            radius: 42,
          ),
        ],
      ),
    );
  }
}

class LineChartSample extends StatelessWidget {
  const LineChartSample({super.key});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 5,
        maxY: 30,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 5,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                if (value >= 5 && value <= 30) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 9,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                const months = [
                  "Jan",
                  "Feb",
                  "Mar",
                  "Apr",
                  "May",
                  "Jun",
                  "Jul",
                  "Aug",
                  "Sep",
                  "Oct",
                  "Nov",
                  "Dec",
                ];
                if (value.toInt() >= 0 && value.toInt() < months.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      months[value.toInt()],
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 9,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          drawVerticalLine: true,
          horizontalInterval: 5,
          verticalInterval: 1,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: const Color(0xFFE5E7EB), strokeWidth: 1),
          getDrawingVerticalLine: (value) =>
              FlLine(color: const Color(0xFFF3F4F6), strokeWidth: 1),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            spots: const [
              FlSpot(0, 10),
              FlSpot(1, 15),
              FlSpot(2, 12),
              FlSpot(3, 18),
              FlSpot(4, 22),
              FlSpot(5, 25),
              FlSpot(6, 28),
              FlSpot(7, 20),
              FlSpot(8, 26),
              FlSpot(9, 30),
              FlSpot(10, 24),
              FlSpot(11, 29),
            ],
            dotData: FlDotData(show: false),
            color: const Color(0xFF2563EB),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF2563EB).withOpacity(0.15),
            ),
            barWidth: 3,
          ),
        ],
      ),
    );
  }
}

// Small legend dot used under the chart
class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
