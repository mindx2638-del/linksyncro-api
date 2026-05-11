import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// A utility class to handle media deletion operations using [PhotoManager].
class VideoDelete {
  
  /// Deletes a list of [AssetEntity] from the device storage.
  /// This triggers the system's native permission dialog (Android 10+ / iOS).
  static Future<bool> deleteAssets(List<AssetEntity> assets) async {
    if (assets.isEmpty) return true;
    
    try {
      final List<String> ids = assets.map((asset) => asset.id).toList();
      final List<String> deletedIds = await PhotoManager.editor.deleteWithIds(ids);
      
      // Return true if all requested assets were deleted
      return deletedIds.length == assets.length;
    } catch (e) {
      debugPrint("Error performing batch deletion: $e");
      return false;
    }
  }

  /// Deletes a single video [AssetEntity].
  static Future<bool> deleteSingleVideo(AssetEntity video) async {
    return await deleteAssets([video]);
  }

  /// Deletes all videos within a specific [AssetPathEntity] (Folder).
  /// Limits to 5000 items to prevent memory overflow.
  static Future<bool> deleteFullFolder(AssetPathEntity folder) async {
    try {
      final List<AssetEntity> assets = await folder.getAssetListRange(start: 0, end: 5000);
      return await deleteAssets(assets);
    } catch (e) {
      debugPrint("Error deleting folder: $e");
      return false;
    }
  }

  /// Shows a professional confirmation dialog before deletion.
  /// [itemCount] can be used to show how many items are being deleted.
  static Future<bool> showConfirmDialog({
    required BuildContext context,
    required String title,
    String? message,
    int? itemCount,
  }) async {
    final String contentText = message ?? 
        "Are you sure you want to permanently delete ${itemCount != null ? '$itemCount items' : 'this item'}? This action cannot be undone.";

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(contentText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("DELETE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }
}
