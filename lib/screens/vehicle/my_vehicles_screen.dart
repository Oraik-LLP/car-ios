import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vehicle.dart';
import '../../services/vehicle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neuomorphic.dart';
import 'add_vehicle_screen.dart';

class MyVehiclesScreen extends StatelessWidget {
  const MyVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Vehicles')),
      body: AppBackground(
        child: ListenableBuilder(
          listenable: VehicleService.instance,
          builder: (context, _) {
            final vehicles = VehicleService.instance.vehicles;
            final selected = VehicleService.instance.selected;

            if (vehicles.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_car_rounded,
                        size: 56, color: AppColors.textTertiary),
                    const SizedBox(height: 16),
                    Text('No vehicles added yet', style: tt.bodyLarge),
                    const SizedBox(height: 24),
                    NeuPrimaryButton(
                      expanded: false,
                      label: 'Add Vehicle',
                      icon: Icons.add_rounded,
                      onPressed: () => _openAdd(context),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    itemCount: vehicles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final v = vehicles[i];
                      final isSel = v.id == selected?.id;
                      return _VehicleCard(
                        vehicle: v,
                        isSelected: isSel,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          VehicleService.instance.select(v);
                        },
                        onDelete: () => _confirmDelete(context, v),
                        onEditVin: () => _editVin(context, v),
                      );
                    },
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: NeuPrimaryButton(
                    label: 'Add Another Vehicle',
                    icon: Icons.add_rounded,
                    onPressed: () => _openAdd(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openAdd(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<Vehicle>(builder: (_) => const AddVehicleScreen()),
    );
  }

  Future<void> _editVin(BuildContext context, Vehicle vehicle) async {
    final controller = TextEditingController(text: vehicle.vin ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Vehicle VIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Optional. A VIN can improve vehicle-specific guidance. It stays on this device and is excluded from AI requests.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLength: 17,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[A-HJ-NPR-Za-hj-npr-z0-9]'),
                ),
                LengthLimitingTextInputFormatter(17),
              ],
              decoration: const InputDecoration(
                labelText: '17-character VIN',
                hintText: 'Skip or add it later',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true) {
      final vin = controller.text.trim().toUpperCase();
      await VehicleService.instance.upsert(
        vehicle.copyWith(vin: vin.isEmpty ? null : vin, clearVin: vin.isEmpty),
      );
    }
    controller.dispose();
  }

  void _confirmDelete(BuildContext context, Vehicle v) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove vehicle?'),
        content: Text('This will delete ${v.displayName}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              VehicleService.instance.remove(v.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onEditVin,
  });
  final Vehicle vehicle;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEditVin;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: NeuPane(
        borderRadius: 18,
        child: Row(
          children: [
            VehicleImageSlot(
              imagePath: vehicle.imagePath,
              size: 72,
              borderRadius: 14,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(vehicle.displayName,
                            style: tt.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Active',
                              style: tt.bodySmall
                                  ?.copyWith(color: AppColors.accent)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${vehicle.fuelLabel} · ${vehicle.mileageKm > 0 ? '${vehicle.mileageKm} km' : 'No mileage'}',
                    style: tt.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vehicle.vin?.isNotEmpty == true
                        ? 'VIN: ${vehicle.vin}'
                        : 'VIN not added · add it later for specific guidance',
                    style: tt.bodySmall?.copyWith(
                      color: vehicle.vin?.isNotEmpty == true
                          ? AppColors.textSecondary
                          : AppColors.accent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            NeuIconButton(
              icon: Icons.edit_outlined,
              size: 36,
              onPressed: onEditVin,
            ),
            const SizedBox(width: 4),
            NeuIconButton(
              icon: Icons.delete_outline_rounded,
              size: 36,
              color: const Color(0x88FF5252),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
