import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'supabase_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

// 常數
const kBucketImages = 'festival_images';
const kBucketMaps = 'festival_maps';

// 工具函式
String pathFromPublicUrl(String publicUrl, String bucket) {
  final marker = '/object/public/$bucket/';
  final idx = publicUrl.indexOf(marker);
  if (idx == -1) return '';
  return publicUrl.substring(idx + marker.length);
}

class OrganizerHomeScreen extends StatefulWidget {
  const OrganizerHomeScreen({super.key});

  @override
  State<OrganizerHomeScreen> createState() => _OrganizerHomeScreenState();
}

class _OrganizerHomeScreenState extends State<OrganizerHomeScreen> {
  XFile? pickedImage;
  XFile? pickedMap;
  Uint8List? _pickedMapData;
  String? pickedMapName;
  XFile? pickedMapForEdit;

  final CropController _cropController = CropController();
  Uint8List? _croppedData;
  String? croppedImageName;

  Future<void> _refreshFestivals() async {
    final loaded = await SupabaseService().getFestivals();
    final uniqueFestivals = <String, Map<String, dynamic>>{};

    for (var fest in loaded) {
      final key = '${fest['name']}_${fest['start']}_${fest['end']}';
      uniqueFestivals[key] = fest;
    }
    final today = DateTime.now();
    setState(() {
      festivals =
          uniqueFestivals.values
              .where(
                (fest) =>
                    DateTime.parse(fest['end']).isAfter(today) ||
                    DateTime.parse(fest['end']).isAtSameMomentAs(today),
              )
              .toList()
            ..sort((a, b) => a['start'].compareTo(b['start']));
    });
  }

  List<Map<String, dynamic>> festivals = [];

  Future<String> uploadCompressedImageToSupabase(XFile pickedImage) async {
    final bytes = await pickedImage.readAsBytes();
    final originalImage = img.decodeImage(bytes);
    if (originalImage == null) throw Exception('無法解碼圖片');

    final compressedBytes = Uint8List.fromList(
      img.encodeJpg(originalImage, quality: 80),
    );

    final uuid = const Uuid().v4();
    final safeFileName = '$uuid.jpg';

    await Supabase.instance.client.storage
        .from(kBucketImages)
        .uploadBinary(
          safeFileName,
          compressedBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    final publicUrl = Supabase.instance.client.storage
        .from(kBucketImages)
        .getPublicUrl(safeFileName);

    return publicUrl;
  }

  @override
  void initState() {
    super.initState();
    SupabaseService().getFestivals().then((loaded) {
      // 自動過濾重複（以 name+start+end 作為識別）
      final uniqueFestivals = <String, Map<String, dynamic>>{};

      for (var fest in loaded) {
        final key = '${fest['name']}_${fest['start']}_${fest['end']}';
        uniqueFestivals[key] = fest; // 相同 key 的自動覆蓋
      }

      final today = DateTime.now();
      setState(() {
        festivals =
            uniqueFestivals.values
                .where(
                  (fest) =>
                      DateTime.parse(fest['end']).isAfter(today) ||
                      DateTime.parse(fest['end']).isAtSameMomentAs(today),
                )
                .toList();
        festivals.sort((a, b) => b['start'].compareTo(a['start']));
      });
    });
  }

  void _openFestivalDetail(int index) async {
    final fest = festivals[index];

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => FestivalManageScreen(
              festival: fest,
              onUpdate: (updated) {
                // 這邊不需要自己updateSupabase，只要更新畫面，真正存資料是下面 result 不為null時做！
                setState(() => festivals[index] = updated);
              },
            ),
      ),
    );

    if (result != null) {
      final updatedFestival =
          {
            ...festivals[index],
            ...result,
            'id': festivals[index]['id'],
          }.cast<String, dynamic>();

      setState(() {
        festivals[index] = updatedFestival;
      });

      await SupabaseService().updateFestival(
        updatedFestival['id'],
        updatedFestival,
      );
    }
  }

  void _onImageSelected(
    Uint8List imageData,
    XFile pickedImage,
    StateSetter setStateDialog,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            '裁切封面圖片', // 🔥 這裡加標題！
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          content: SizedBox(
            width: 300,
            height: 400,
            child: Column(
              children: [
                Expanded(
                  child: Crop(
                    controller: _cropController,
                    image: imageData,
                    aspectRatio: 1, // ⭐ 正方形
                    onCropped: (croppedData) {
                      setState(() {
                        _croppedData = croppedData;
                        croppedImageName = '(已裁切封面) ${pickedImage.name}';
                      });

                      setStateDialog(() {}); // 🔥 同時刷新 Dialog
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    _cropController.crop(); // ⭐ 按下去裁切
                  },
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddFestivalDialog() async {
    late StateSetter setStateDialog; // 🔥 記得加這個
    bool isLoading = false;

    String name = '';
    DateTime? startDate;
    DateTime? endDate;
    String city = '';
    bool isPaid = false;

    String? mapUrl;

    final picker = ImagePicker();

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            setStateDialog = setState;
            return AlertDialog(
              title: const Text('新增音樂祭'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(labelText: '音樂祭名稱'),
                      onChanged: (value) => name = value,
                    ),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: '縣市'),
                      value: city.isEmpty ? null : city,
                      items:
                          [
                                '基隆市',
                                '台北市',
                                '新北市',
                                '桃園市',
                                '新竹市',
                                '新竹縣',
                                '苗栗縣',
                                '台中市',
                                '彰化縣',
                                '南投縣',
                                '雲林縣',
                                '嘉義市',
                                '嘉義縣',
                                '台南市',
                                '高雄市',
                                '屏東縣',
                                '台東縣',
                                '花蓮縣',
                                '宜蘭縣',
                                '澎湖縣',
                              ]
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                      onChanged: (value) {
                        setState(() {
                          city = value ?? '';
                        });
                      },
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('是否為付費活動'),
                        Switch(
                          value: isPaid,
                          onChanged: (value) {
                            setState(() {
                              isPaid = value;
                            });
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('起始日：'),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() => startDate = picked);
                            }
                          },
                          child: Text(
                            startDate == null
                                ? '選擇'
                                : '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('結束日：'),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: startDate ?? DateTime.now(),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() => endDate = picked);
                            }
                          },
                          child: Text(
                            endDate == null
                                ? '選擇'
                                : '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text('新增封面：'),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.photo),
                          label: const Text('選擇圖片'),
                          onPressed: () async {
                            final picked = await picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 80,
                            );
                            if (picked != null) {
                              final bytes = await picked.readAsBytes();
                              pickedImage = picked;
                              _onImageSelected(bytes, picked, setState);
                            }
                          },
                        ),
                      ],
                    ),

                    if (croppedImageName != null)
                      Text('已選圖片：$croppedImageName')
                    else if (pickedImage != null)
                      Text('已選圖片：${pickedImage!.name}'),

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text('新增地圖：'),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.map),
                          label: const Text('選擇圖片'),
                          onPressed: () async {
                            final picked = await picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 80,
                            );
                            if (picked != null) {
                              final bytes = await picked.readAsBytes();
                              pickedMap = picked;
                              _pickedMapData = bytes;
                              pickedMapName = picked.name;
                              setStateDialog(() {}); // 這行刷新 Dialog 顯示
                            }
                          },
                        ),
                      ],
                    ),
                    if (pickedMapName != null) Text('已選地圖：$pickedMapName'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed:
                      isLoading
                          ? null
                          : () async {
                            setStateDialog(() {
                              isLoading = true; // 🔥開始進入loading
                            });

                            try {
                              if (name.isNotEmpty &&
                                  startDate != null &&
                                  endDate != null) {
                                try {
                                  Uint8List? imageDataForUpload;

                                  if (_croppedData != null &&
                                      _croppedData!.isNotEmpty) {
                                    imageDataForUpload = _croppedData;
                                  } else if (pickedImage != null) {
                                    final bytes =
                                        await pickedImage!.readAsBytes();
                                    if (bytes.isNotEmpty) {
                                      imageDataForUpload = bytes;
                                    }
                                  }

                                  String? imageUrl;
                                  if (imageDataForUpload != null) {
                                    // 🔥 這裡補壓縮
                                    final originalImage = img.decodeImage(
                                      imageDataForUpload,
                                    );
                                    if (originalImage == null) {
                                      throw Exception('無法解碼圖片');
                                    }
                                    final compressedBytes = Uint8List.fromList(
                                      img.encodeJpg(originalImage, quality: 80),
                                    );

                                    final uuid = const Uuid().v4();
                                    final safeFileName = '$uuid.jpg';

                                    await Supabase.instance.client.storage
                                        .from(kBucketImages) // ❗改 bucket
                                        .uploadBinary(
                                          safeFileName,
                                          compressedBytes,
                                          fileOptions: const FileOptions(
                                            upsert: true,
                                            contentType: 'image/jpeg',
                                          ),
                                        );

                                    imageUrl = Supabase.instance.client.storage
                                        .from(kBucketImages) // ❗改 bucket
                                        .getPublicUrl(safeFileName);
                                  }

                                  // 🔥 地圖圖片一樣補壓縮
                                  if (_pickedMapData != null &&
                                      _pickedMapData!.isNotEmpty) {
                                    final originalMapImage = img.decodeImage(
                                      _pickedMapData!,
                                    );
                                    if (originalMapImage == null) {
                                      throw Exception('無法解碼地圖圖片');
                                    }
                                    final compressedMapBytes =
                                        Uint8List.fromList(
                                          img.encodeJpg(
                                            originalMapImage,
                                            quality: 80,
                                          ),
                                        );

                                    final uuid = const Uuid().v4();
                                    final safeFileName = '$uuid.jpg';

                                    await Supabase.instance.client.storage
                                        .from(kBucketMaps) // ❗改 bucket
                                        .uploadBinary(
                                          safeFileName,
                                          compressedMapBytes,
                                          fileOptions: const FileOptions(
                                            upsert: true,
                                            contentType: 'image/jpeg',
                                          ),
                                        );

                                    mapUrl = Supabase.instance.client.storage
                                        .from(kBucketMaps) // ❗改 bucket
                                        .getPublicUrl(safeFileName);
                                  }

                                  await SupabaseService().addFestival({
                                    'name': name,
                                    'start':
                                        '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}',
                                    'end':
                                        '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}',
                                    'city': city,
                                    'isPaid': isPaid,
                                    'stages': [],
                                    'image': imageUrl ?? '',
                                    'map': mapUrl ?? '',
                                  });
                                  await _refreshFestivals();
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('新增成功！'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }

                                  _croppedData = null;
                                  pickedImage = null;
                                } catch (e) {
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder:
                                          (_) => AlertDialog(
                                            title: const Text('錯誤'),
                                            content: Text('新增失敗：$e'),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () =>
                                                        Navigator.pop(context),
                                                child: const Text('確定'),
                                              ),
                                            ],
                                          ),
                                    );
                                  }
                                }
                              }
                            } finally {
                              if (mounted) {
                                setStateDialog(() {
                                  isLoading = false; // 🔥完成或失敗都結束loading
                                });
                              }
                            }
                          },
                  child:
                      isLoading
                          ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                          : const Text('新增'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '主辦模式',
          style: TextStyle(
            color: Color.fromARGB(255, 231, 190, 123),
            fontWeight: FontWeight.bold, // 粗體
          ), // ⭐ 字體顏色
        ),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 40, 60, 70),
        iconTheme: const IconThemeData(
          color: Color.fromARGB(255, 231, 190, 123),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(
          bottom: 10.0,
          right: 20.0,
        ), // ⬅️ 避開 BottomNavigationBar
        child: FloatingActionButton(
          onPressed: _showAddFestivalDialog, // ← 每頁這個可以換成自己頁面要用的
          backgroundColor: const Color.fromARGB(255, 255, 255, 255),
          child: const Icon(Icons.add),
        ),
      ),

      body: SafeArea(
        child:
            festivals.isEmpty
                ? const Center(child: Text('尚未建立任何音樂祭'))
                : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 200),
                  itemCount: festivals.length,
                  itemBuilder: (context, index) {
                    final festival = festivals[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(50),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ListTile(
                        title: Row(children: [Text(festival['name'])]),

                        subtitle: Text(
                          '${festival['city']}｜${festival['start']} ~ ${festival['end']}',
                        ),
                        onTap: () => _openFestivalDetail(index),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final current = festivals[index];

                                Uint8List? pickedMapDataForEdit;
                                String? pickedMapNameForEdit;

                                String name = current['name'] ?? '';
                                String city = current['city'] ?? '';
                                bool isPaid = current['isPaid'] ?? false;
                                DateTime? startDate = DateTime.tryParse(
                                  current['start'] ?? '',
                                );
                                DateTime? endDate = DateTime.tryParse(
                                  current['end'] ?? '',
                                );

                                final picker = ImagePicker();

                                await showDialog(
                                  context: context,
                                  builder:
                                      (_) => StatefulBuilder(
                                        builder:
                                            (context, setState) => AlertDialog(
                                              title: const Text('編輯音樂祭'),
                                              content: SingleChildScrollView(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    TextField(
                                                      decoration:
                                                          const InputDecoration(
                                                            labelText: '音樂祭名稱',
                                                          ),
                                                      controller:
                                                          TextEditingController(
                                                            text: name,
                                                          ),
                                                      onChanged:
                                                          (value) =>
                                                              name = value,
                                                    ),
                                                    DropdownButtonFormField<
                                                      String
                                                    >(
                                                      decoration:
                                                          const InputDecoration(
                                                            labelText: '縣市',
                                                          ),
                                                      value:
                                                          city.isEmpty
                                                              ? null
                                                              : city,
                                                      items:
                                                          [
                                                                '基隆市',
                                                                '台北市',
                                                                '新北市',
                                                                '桃園市',
                                                                '新竹市',
                                                                '新竹縣',
                                                                '苗栗縣',
                                                                '台中市',
                                                                '彰化縣',
                                                                '南投縣',
                                                                '雲林縣',
                                                                '嘉義市',
                                                                '嘉義縣',
                                                                '台南市',
                                                                '高雄市',
                                                                '屏東縣',
                                                                '台東縣',
                                                                '花蓮縣',
                                                                '宜蘭縣',
                                                                '澎湖縣',
                                                              ]
                                                              .map(
                                                                (c) =>
                                                                    DropdownMenuItem(
                                                                      value: c,
                                                                      child:
                                                                          Text(
                                                                            c,
                                                                          ),
                                                                    ),
                                                              )
                                                              .toList(),
                                                      onChanged:
                                                          (value) =>
                                                              city =
                                                                  value ?? '',
                                                    ),
                                                    SwitchListTile(
                                                      title: const Text(
                                                        '是否為付費活動',
                                                      ),
                                                      value: isPaid,
                                                      onChanged:
                                                          (value) => setState(
                                                            () =>
                                                                isPaid = value,
                                                          ),
                                                    ),
                                                    Row(
                                                      children: [
                                                        const Text('起始日：'),
                                                        TextButton(
                                                          onPressed: () async {
                                                            final picked =
                                                                await showDatePicker(
                                                                  context:
                                                                      context,
                                                                  initialDate:
                                                                      startDate ??
                                                                      DateTime.now(),
                                                                  firstDate:
                                                                      DateTime(
                                                                        2020,
                                                                      ),
                                                                  lastDate:
                                                                      DateTime(
                                                                        2030,
                                                                      ),
                                                                );
                                                            if (picked !=
                                                                null) {
                                                              setState(
                                                                () =>
                                                                    startDate =
                                                                        picked,
                                                              );
                                                            }
                                                          },
                                                          child: Text(
                                                            startDate == null
                                                                ? '選擇'
                                                                : '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Row(
                                                      children: [
                                                        const Text('結束日：'),
                                                        TextButton(
                                                          onPressed: () async {
                                                            final picked =
                                                                await showDatePicker(
                                                                  context:
                                                                      context,
                                                                  initialDate:
                                                                      endDate ??
                                                                      DateTime.now(),
                                                                  firstDate:
                                                                      startDate ??
                                                                      DateTime.now(),
                                                                  lastDate:
                                                                      DateTime(
                                                                        2030,
                                                                      ),
                                                                );
                                                            if (picked !=
                                                                null) {
                                                              setState(
                                                                () =>
                                                                    endDate =
                                                                        picked,
                                                              );
                                                            }
                                                          },
                                                          child: Text(
                                                            endDate == null
                                                                ? '選擇'
                                                                : '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Row(
                                                      children: [
                                                        const Text('新增封面:'),
                                                        const SizedBox(
                                                          width: 12,
                                                        ),
                                                        ElevatedButton.icon(
                                                          icon: const Icon(
                                                            Icons.photo,
                                                          ),
                                                          label: const Text(
                                                            '更換圖片',
                                                          ),
                                                          onPressed: () async {
                                                            final picked = await picker
                                                                .pickImage(
                                                                  source:
                                                                      ImageSource
                                                                          .gallery,
                                                                  imageQuality:
                                                                      80,
                                                                );
                                                            if (picked !=
                                                                null) {
                                                              setState(() {
                                                                pickedImage =
                                                                    picked;
                                                              });
                                                            }
                                                          },
                                                        ),
                                                      ],
                                                    ),

                                                    if (pickedImage != null)
                                                      Text(
                                                        '已選圖片：${pickedImage!.name}',
                                                      ),

                                                    const SizedBox(height: 10),
                                                    Row(
                                                      children: [
                                                        const Text('更換地圖:'),
                                                        const SizedBox(
                                                          width: 12,
                                                        ),
                                                        ElevatedButton.icon(
                                                          icon: const Icon(
                                                            Icons.map,
                                                          ),
                                                          label: const Text(
                                                            '選擇圖片',
                                                          ),
                                                          onPressed: () async {
                                                            final picked = await picker
                                                                .pickImage(
                                                                  source:
                                                                      ImageSource
                                                                          .gallery,
                                                                  imageQuality:
                                                                      80,
                                                                );
                                                            if (picked !=
                                                                null) {
                                                              final bytes =
                                                                  await picked
                                                                      .readAsBytes();
                                                              pickedMapForEdit =
                                                                  picked;
                                                              pickedMapDataForEdit =
                                                                  bytes;
                                                              pickedMapNameForEdit =
                                                                  picked.name;
                                                              setState(() {});
                                                            }
                                                          },
                                                        ),
                                                      ],
                                                    ),

                                                    if (pickedMapNameForEdit !=
                                                        null)
                                                      Text(
                                                        '已選地圖：$pickedMapNameForEdit',
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        context,
                                                      ),
                                                  child: const Text('取消'),
                                                ),

                                                ElevatedButton(
                                                  onPressed: () async {
                                                    String? imageUrl =
                                                        current['image'];
                                                    String? mapUrl =
                                                        current['map'];
                                                    if (pickedImage != null) {
                                                      final bytes =
                                                          await pickedImage!
                                                              .readAsBytes();
                                                      if (bytes.isNotEmpty) {
                                                        imageUrl =
                                                            await uploadCompressedImageToSupabase(
                                                              pickedImage!,
                                                            );
                                                      }
                                                    }
                                                    if (pickedMapDataForEdit !=
                                                            null &&
                                                        pickedMapDataForEdit!
                                                            .isNotEmpty) {
                                                      final uuid =
                                                          const Uuid().v4();
                                                      final safeFileName =
                                                          '$uuid.jpg';

                                                      await Supabase
                                                          .instance
                                                          .client
                                                          .storage
                                                          .from('kBucketImages')
                                                          .uploadBinary(
                                                            safeFileName,
                                                            pickedMapDataForEdit!,
                                                            fileOptions:
                                                                const FileOptions(
                                                                  upsert: true,
                                                                  contentType:
                                                                      'image/jpeg',
                                                                ),
                                                          );

                                                      mapUrl = Supabase
                                                          .instance
                                                          .client
                                                          .storage
                                                          .from('kBucketMaps')
                                                          .getPublicUrl(
                                                            safeFileName,
                                                          );
                                                    }

                                                    final updated = {
                                                      'id': current['id'],
                                                      'name': name,
                                                      'start':
                                                          '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}',
                                                      'end':
                                                          '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}',
                                                      'city': city,
                                                      'isPaid': isPaid,
                                                      'image': imageUrl,
                                                      'stages':
                                                          current['stages'],
                                                      if (mapUrl != null)
                                                        'map': mapUrl,
                                                    };

                                                    setState(
                                                      () =>
                                                          festivals[index] =
                                                              updated,
                                                    );
                                                    await SupabaseService()
                                                        .updateFestival(
                                                          current['id'],
                                                          updated,
                                                        );
                                                    await _refreshFestivals();
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '儲存成功！',
                                                          ),
                                                          duration: Duration(
                                                            seconds: 2,
                                                          ),
                                                        ),
                                                      );
                                                    }

                                                    Navigator.pop(context);
                                                  },
                                                  child: const Text('儲存'),
                                                ),
                                              ],
                                            ),
                                      ),
                                );
                              },
                            ),

                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () async {
                                final TextEditingController passwordController =
                                    TextEditingController();
                                String? errorText;

                                final passwordConfirmed = await showDialog<
                                  bool
                                >(
                                  context: context,
                                  builder: (_) {
                                    return StatefulBuilder(
                                      builder:
                                          (
                                            context,
                                            setStateDialog,
                                          ) => AlertDialog(
                                            title: const Text('請輸入刪除密碼'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                TextField(
                                                  controller:
                                                      passwordController,
                                                  obscureText: true,
                                                  decoration: InputDecoration(
                                                    hintText: '輸入密碼',
                                                    errorText: errorText,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () => Navigator.pop(
                                                      context,
                                                      false,
                                                    ),
                                                child: const Text('取消'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () async {
                                                  final inputPassword =
                                                      passwordController.text
                                                          .trim();
                                                  final realPassword =
                                                      await SupabaseService()
                                                          .getOrganizerDeletePassword();

                                                  if (realPassword == null) {
                                                    if (context.mounted) {
                                                      Navigator.pop(
                                                        context,
                                                        false,
                                                      );
                                                      showDialog(
                                                        context: context,
                                                        builder:
                                                            (_) => AlertDialog(
                                                              title: const Text(
                                                                '錯誤',
                                                              ),
                                                              content: const Text(
                                                                '無法讀取刪除密碼，請稍後再試。',
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed:
                                                                      () => Navigator.pop(
                                                                        context,
                                                                      ),
                                                                  child:
                                                                      const Text(
                                                                        '確定',
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  if (inputPassword ==
                                                      realPassword) {
                                                    Navigator.pop(
                                                      context,
                                                      true,
                                                    );
                                                  } else {
                                                    setStateDialog(() {
                                                      passwordController
                                                          .clear();
                                                      errorText = '密碼錯誤，請重新輸入';
                                                    });
                                                  }
                                                },
                                                child: const Text('確認'),
                                              ),
                                            ],
                                          ),
                                    );
                                  },
                                );

                                if (passwordConfirmed != true) {
                                  return;
                                }

                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder:
                                      (_) => AlertDialog(
                                        title: const Text('刪除確認'),
                                        content: Text(
                                          '確定要刪除「${festival['name']}」這個音樂祭？',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                            child: const Text('取消'),
                                          ),
                                          ElevatedButton(
                                            onPressed:
                                                () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                            child: const Text('刪除'),
                                          ),
                                        ],
                                      ),
                                );

                                if (confirmed == true) {
                                  final festivalToDelete = festivals[index];

                                  try {
                                    final imageUrl = festivalToDelete['image'];
                                    if (imageUrl != null &&
                                        imageUrl.isNotEmpty) {
                                      final pathInBucket = pathFromPublicUrl(
                                        imageUrl,
                                        kBucketImages,
                                      );
                                      if (pathInBucket.isNotEmpty) {
                                        await Supabase.instance.client.storage
                                            .from(kBucketImages) // ❗改 bucket
                                            .remove([pathInBucket]);
                                      }
                                    }

                                    final mapUrl = festivalToDelete['map'];
                                    if (mapUrl != null && mapUrl.isNotEmpty) {
                                      final pathInBucket = pathFromPublicUrl(
                                        mapUrl,
                                        kBucketMaps,
                                      );
                                      if (pathInBucket.isNotEmpty) {
                                        await Supabase.instance.client.storage
                                            .from(kBucketMaps) // ❗改 bucket
                                            .remove([pathInBucket]);
                                      }
                                    }
                                  } catch (e) {
                                    print('刪除Storage圖片失敗：$e');
                                  }

                                  await SupabaseService().deleteFestival(
                                    festivalToDelete['id'],
                                  );

                                  setState(() {
                                    festivals.removeAt(index);
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}

class FestivalManageScreen extends StatefulWidget {
  final Map<String, dynamic> festival;
  final Function(Map<String, dynamic>) onUpdate;

  const FestivalManageScreen({
    super.key,
    required this.festival,
    required this.onUpdate,
  });

  @override
  State<FestivalManageScreen> createState() => _FestivalManageScreenState();
}

class _FestivalManageScreenState extends State<FestivalManageScreen> {
  final List<Color> _presetColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.yellow,
    Colors.pink,
    Colors.teal,
    Colors.cyan,
    Colors.amber,
  ];

  Color _parseHexColor(String? hex) {
    try {
      return Color(int.parse((hex ?? '#3F51B5').replaceFirst('#', '0xff')));
    } catch (_) {
      return Colors.indigo;
    }
  }

  late List<Map<String, dynamic>> stages;
  late List<String> tabLabels;
  late List<String> tabKeys;

  @override
  void initState() {
    super.initState();
    stages = List<Map<String, dynamic>>.from(widget.festival['stages']);
    final result = _generateTabs(
      widget.festival['start'],
      widget.festival['end'],
    );
    tabLabels = result['labels']!;
    tabKeys = result['keys']!;
  }

  Map<String, List<String>> _generateTabs(String start, String end) {
    final startDate = DateTime.parse(start);
    final endDate = DateTime.parse(end);
    List<String> labels = [];
    List<String> keys = [];
    DateTime current = startDate;
    while (!current.isAfter(endDate)) {
      labels.add('${current.month}/${current.day}');
      keys.add(
        '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}',
      );
      current = current.add(const Duration(days: 1));
    }
    return {'labels': labels, 'keys': keys};
  }

  void _addPerformance(int stageIndex, String dateKey) async {
    final bandController = TextEditingController();
    TimeOfDay? start;
    TimeOfDay? end;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text('新增節目'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: bandController,
                        decoration: const InputDecoration(labelText: '樂團名稱'),
                      ),
                      Row(
                        children: [
                          const Text('開始'),
                          TextButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(
                                  hour: 12,
                                  minute: 0,
                                ),
                              );
                              if (picked != null) {
                                setState(() => start = picked);
                              }
                            },
                            child: Text(
                              start == null
                                  ? '選擇時間'
                                  : '${start!.hour.toString().padLeft(2, '0')}:${start!.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('結束'),
                          TextButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(
                                  hour: 13,
                                  minute: 0,
                                ),
                              );
                              if (picked != null) setState(() => end = picked);
                            },
                            child: Text(
                              end == null
                                  ? '選擇時間'
                                  : '${end!.hour.toString().padLeft(2, '0')}:${end!.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (bandController.text.isNotEmpty &&
                            start != null &&
                            end != null) {
                          Navigator.pop(context, {
                            'band': bandController.text,
                            'time':
                                '${start!.hour.toString().padLeft(2, '0')}:${start!.minute.toString().padLeft(2, '0')} - ${end!.hour.toString().padLeft(2, '0')}:${end!.minute.toString().padLeft(2, '0')}',
                          });
                        }
                      },
                      child: const Text('新增'),
                    ),
                  ],
                ),
          ),
    );

    if (result != null) {
      setState(() {
        final stage = stages[stageIndex];
        stage['performances'] ??= {};
        stage['performances'][dateKey] ??= [];
        stage['performances'][dateKey].add(result);
      });
    }
  }

  void _saveAndExit() {
    final updated = {
      if (widget.festival['id'] != null) 'id': widget.festival['id'],
      'name': widget.festival['name'] ?? '',
      'start': widget.festival['start'] ?? '',
      'end': widget.festival['end'] ?? '',
      'stages': stages,
      'image': widget.festival['image'] ?? '',
      'city': widget.festival['city'] ?? '',
      'isPaid': widget.festival['isPaid'] ?? false,
    };
    widget.onUpdate(updated); // 即時更新父層
    Navigator.pop(context, updated); // 回傳更新資料
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _saveAndExit();
        return false;
      },
      child: DefaultTabController(
        length: tabLabels.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              '${widget.festival['name']} 管理',
              style: TextStyle(
                color: const Color.fromARGB(255, 231, 190, 123),
              ), // ⭐ 字體顏色
            ),
            centerTitle: true,
            backgroundColor: Color.fromARGB(255, 40, 60, 70),
            iconTheme: const IconThemeData(
              color: Color.fromARGB(255, 231, 190, 123),
            ),
            bottom: TabBar(
              isScrollable: false,
              labelPadding: const EdgeInsets.symmetric(horizontal: 30),
              labelStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 231, 190, 123),
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: Color.fromARGB(150, 231, 190, 123),
              ),
              indicatorColor: Color.fromARGB(255, 231, 190, 123), // 線的顏色
              indicatorWeight: 4.0, // 線的粗細
              indicatorPadding: EdgeInsets.symmetric(horizontal: 10), // 左右內縮
              tabs: tabLabels.map((label) => Tab(text: label)).toList(),
            ),
          ),
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 10.0, right: 20.0), // 避開底部欄
            child: FloatingActionButton(
              backgroundColor: const Color.fromARGB(255, 255, 255, 255),
              child: const Icon(Icons.add),
              onPressed: () async {
                final stageNameController = TextEditingController();
                Color selectedColor = Colors.indigo;

                final newStage = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder:
                      (_) => StatefulBuilder(
                        builder:
                            (context, setState) => AlertDialog(
                              title: const Text('新增舞台'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: stageNameController,
                                    decoration: const InputDecoration(
                                      labelText: '舞台名稱',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Text('顏色：'),
                                      Container(
                                        width: 24,
                                        height: 24,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selectedColor,
                                          border: Border.all(
                                            color: Colors.black,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          final rController =
                                              TextEditingController();
                                          final gController =
                                              TextEditingController();
                                          final bController =
                                              TextEditingController();
                                          Color tempColor = selectedColor;

                                          void updateControllers(Color color) {
                                            rController.text =
                                                color.red.toString();
                                            gController.text =
                                                color.green.toString();
                                            bController.text =
                                                color.blue.toString();
                                          }

                                          updateControllers(tempColor);

                                          final picked = await showDialog<
                                            Color
                                          >(
                                            context: context,
                                            builder:
                                                (_) => StatefulBuilder(
                                                  builder:
                                                      (
                                                        context,
                                                        setStateDialog,
                                                      ) => AlertDialog(
                                                        title: const Text(
                                                          '選擇顏色',
                                                        ),
                                                        content: SingleChildScrollView(
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              ColorPicker(
                                                                pickerColor:
                                                                    tempColor,
                                                                onColorChanged: (
                                                                  color,
                                                                ) {
                                                                  tempColor =
                                                                      color;
                                                                  updateControllers(
                                                                    color,
                                                                  );
                                                                  setState(
                                                                    () {},
                                                                  );
                                                                  setStateDialog(
                                                                    () {},
                                                                  );
                                                                },
                                                                enableAlpha:
                                                                    false,
                                                                labelTypes: [],
                                                                pickerAreaHeightPercent:
                                                                    0.7,
                                                              ),
                                                              Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: TextField(
                                                                      controller:
                                                                          rController,
                                                                      keyboardType:
                                                                          TextInputType
                                                                              .number,
                                                                      decoration: const InputDecoration(
                                                                        labelText:
                                                                            'R',
                                                                      ),
                                                                      onChanged: (
                                                                        value,
                                                                      ) {
                                                                        final r =
                                                                            int.tryParse(
                                                                              value,
                                                                            ) ??
                                                                            0;
                                                                        tempColor = tempColor.withRed(
                                                                          r.clamp(
                                                                            0,
                                                                            255,
                                                                          ),
                                                                        );
                                                                        updateControllers(
                                                                          tempColor,
                                                                        );
                                                                        setState(
                                                                          () {},
                                                                        );
                                                                        setStateDialog(
                                                                          () {},
                                                                        );
                                                                      },
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Expanded(
                                                                    child: TextField(
                                                                      controller:
                                                                          gController,
                                                                      keyboardType:
                                                                          TextInputType
                                                                              .number,
                                                                      decoration: const InputDecoration(
                                                                        labelText:
                                                                            'G',
                                                                      ),
                                                                      onChanged: (
                                                                        value,
                                                                      ) {
                                                                        final g =
                                                                            int.tryParse(
                                                                              value,
                                                                            ) ??
                                                                            0;
                                                                        tempColor = tempColor.withGreen(
                                                                          g.clamp(
                                                                            0,
                                                                            255,
                                                                          ),
                                                                        );
                                                                        updateControllers(
                                                                          tempColor,
                                                                        );
                                                                        setState(
                                                                          () {},
                                                                        );
                                                                        setStateDialog(
                                                                          () {},
                                                                        );
                                                                      },
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Expanded(
                                                                    child: TextField(
                                                                      controller:
                                                                          bController,
                                                                      keyboardType:
                                                                          TextInputType
                                                                              .number,
                                                                      decoration: const InputDecoration(
                                                                        labelText:
                                                                            'B',
                                                                      ),
                                                                      onChanged: (
                                                                        value,
                                                                      ) {
                                                                        final b =
                                                                            int.tryParse(
                                                                              value,
                                                                            ) ??
                                                                            0;
                                                                        tempColor = tempColor.withBlue(
                                                                          b.clamp(
                                                                            0,
                                                                            255,
                                                                          ),
                                                                        );
                                                                        updateControllers(
                                                                          tempColor,
                                                                        );
                                                                        setState(
                                                                          () {},
                                                                        );
                                                                        setStateDialog(
                                                                          () {},
                                                                        );
                                                                      },
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                height: 16,
                                                              ),
                                                              Wrap(
                                                                spacing: 8,
                                                                runSpacing: 8,
                                                                children: [
                                                                  ..._presetColors.map(
                                                                    (
                                                                      color,
                                                                    ) => GestureDetector(
                                                                      onTap: () {
                                                                        tempColor =
                                                                            color;
                                                                        updateControllers(
                                                                          color,
                                                                        );
                                                                        setState(
                                                                          () {},
                                                                        );
                                                                        setStateDialog(
                                                                          () {},
                                                                        );
                                                                      },
                                                                      child: Container(
                                                                        width:
                                                                            30,
                                                                        height:
                                                                            30,
                                                                        decoration: BoxDecoration(
                                                                          color:
                                                                              color,
                                                                          shape:
                                                                              BoxShape.circle,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed:
                                                                () =>
                                                                    Navigator.pop(
                                                                      context,
                                                                      null,
                                                                    ),
                                                            child: const Text(
                                                              '取消',
                                                            ),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed:
                                                                () =>
                                                                    Navigator.pop(
                                                                      context,
                                                                      tempColor,
                                                                    ),
                                                            child: const Text(
                                                              '確定',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                ),
                                          );

                                          if (picked != null) {
                                            setState(
                                              () => selectedColor = picked,
                                            );
                                          }
                                        },

                                        child: const Text('選擇顏色'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('取消'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    if (stageNameController.text.isNotEmpty) {
                                      Navigator.pop(context, {
                                        'stage': stageNameController.text,
                                        'color':
                                            '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}',
                                        'performances': {},
                                      });
                                    }
                                  },
                                  child: const Text('新增'),
                                ),
                              ],
                            ),
                      ),
                );

                if (newStage != null) {
                  setState(() {
                    stages.add(newStage);
                  });

                  widget.onUpdate({
                    'id': widget.festival['id'],
                    'name': widget.festival['name'] ?? '',
                    'start': widget.festival['start'] ?? '',
                    'end': widget.festival['end'] ?? '',
                    'stages': stages,
                    'image': widget.festival['image'] ?? '',
                  });
                }
              },
            ),
          ),

          body: TabBarView(
            children: List.generate(tabLabels.length, (tabIndex) {
              final dateKey = tabKeys[tabIndex];
              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  // ★ 包一層可以上下滑動的
                  child: Column(
                    children: List.generate(stages.length, (index) {
                      final stage = stages[index];
                      final rawPerformances =
                          stage['performances'][dateKey] ?? [];
                      final dayPerformances = List<Map<String, dynamic>>.from(
                        rawPerformances,
                      );

                      dayPerformances.sort((a, b) {
                        final timeA = a['time'].split(" - ")[0];
                        final timeB = b['time'].split(" - ")[0];
                        return timeA.compareTo(timeB);
                      });

                      return Card(
                        margin: const EdgeInsets.all(12),
                        child: ExpansionTile(
                          title: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: _parseHexColor(stage['color']),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    stage['stage'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                  ),
                                  onPressed: () async {
                                    final nameController =
                                        TextEditingController(
                                          text: stage['stage'],
                                        );
                                    Color selectedColor = _parseHexColor(
                                      stage['color'],
                                    );

                                    final updatedStage = await showDialog<
                                      Map<String, dynamic>
                                    >(
                                      context: context,
                                      builder:
                                          (_) => StatefulBuilder(
                                            builder:
                                                (
                                                  context,
                                                  setState,
                                                ) => AlertDialog(
                                                  title: const Text('編輯舞台'),
                                                  content: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      TextField(
                                                        controller:
                                                            nameController,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText: '舞台名稱',
                                                            ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Row(
                                                        children: [
                                                          const Text('顏色：'),
                                                          Container(
                                                            width: 24,
                                                            height: 24,
                                                            margin:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  selectedColor,
                                                              border: Border.all(
                                                                color:
                                                                    Colors
                                                                        .black,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: () async {
                                                              final rController =
                                                                  TextEditingController();
                                                              final gController =
                                                                  TextEditingController();
                                                              final bController =
                                                                  TextEditingController();
                                                              Color tempColor =
                                                                  selectedColor; // 用 selectedColor 當初始顏色
                                                              void
                                                              updateControllers(
                                                                Color color,
                                                              ) {
                                                                rController
                                                                        .text =
                                                                    color.red
                                                                        .toString();
                                                                gController
                                                                        .text =
                                                                    color.green
                                                                        .toString();
                                                                bController
                                                                        .text =
                                                                    color.blue
                                                                        .toString();
                                                              }

                                                              final picked = await showDialog<
                                                                Color
                                                              >(
                                                                context:
                                                                    context,
                                                                builder:
                                                                    (
                                                                      _,
                                                                    ) => StatefulBuilder(
                                                                      builder:
                                                                          (
                                                                            context,
                                                                            setStateDialog,
                                                                          ) => AlertDialog(
                                                                            title: const Text(
                                                                              '選擇顏色',
                                                                            ),
                                                                            content: SingleChildScrollView(
                                                                              child: Column(
                                                                                mainAxisSize:
                                                                                    MainAxisSize.min,
                                                                                children: [
                                                                                  ColorPicker(
                                                                                    pickerColor:
                                                                                        tempColor,
                                                                                    onColorChanged: (
                                                                                      color,
                                                                                    ) {
                                                                                      tempColor =
                                                                                          color;
                                                                                      updateControllers(
                                                                                        color,
                                                                                      ); // 拖曳時同步 RGB 欄位
                                                                                      setState(
                                                                                        () {},
                                                                                      );
                                                                                      setStateDialog(
                                                                                        () {},
                                                                                      );
                                                                                    },
                                                                                    enableAlpha:
                                                                                        false,
                                                                                    labelTypes:
                                                                                        [],
                                                                                    pickerAreaHeightPercent:
                                                                                        0.7,
                                                                                  ),

                                                                                  Row(
                                                                                    children: [
                                                                                      Expanded(
                                                                                        child: TextField(
                                                                                          controller:
                                                                                              rController,
                                                                                          keyboardType:
                                                                                              TextInputType.number,
                                                                                          decoration: const InputDecoration(
                                                                                            labelText:
                                                                                                'R',
                                                                                          ),
                                                                                          onChanged: (
                                                                                            value,
                                                                                          ) {
                                                                                            final r =
                                                                                                int.tryParse(
                                                                                                  value,
                                                                                                ) ??
                                                                                                0;
                                                                                            tempColor = tempColor.withRed(
                                                                                              r.clamp(
                                                                                                0,
                                                                                                255,
                                                                                              ),
                                                                                            );
                                                                                            updateControllers(
                                                                                              tempColor,
                                                                                            ); // 保持同步
                                                                                            setState(
                                                                                              () {},
                                                                                            );
                                                                                            setStateDialog(
                                                                                              () {},
                                                                                            );
                                                                                          },
                                                                                        ),
                                                                                      ),
                                                                                      const SizedBox(
                                                                                        width:
                                                                                            8,
                                                                                      ),
                                                                                      Expanded(
                                                                                        child: TextField(
                                                                                          controller:
                                                                                              gController,
                                                                                          keyboardType:
                                                                                              TextInputType.number,
                                                                                          decoration: const InputDecoration(
                                                                                            labelText:
                                                                                                'G',
                                                                                          ),
                                                                                          onChanged: (
                                                                                            value,
                                                                                          ) {
                                                                                            final g =
                                                                                                int.tryParse(
                                                                                                  value,
                                                                                                ) ??
                                                                                                0;
                                                                                            tempColor = tempColor.withGreen(
                                                                                              g.clamp(
                                                                                                0,
                                                                                                255,
                                                                                              ),
                                                                                            );
                                                                                            updateControllers(
                                                                                              tempColor,
                                                                                            );
                                                                                            setState(
                                                                                              () {},
                                                                                            );
                                                                                            setStateDialog(
                                                                                              () {},
                                                                                            );
                                                                                          },
                                                                                        ),
                                                                                      ),
                                                                                      const SizedBox(
                                                                                        width:
                                                                                            8,
                                                                                      ),
                                                                                      Expanded(
                                                                                        child: TextField(
                                                                                          controller:
                                                                                              bController,
                                                                                          keyboardType:
                                                                                              TextInputType.number,
                                                                                          decoration: const InputDecoration(
                                                                                            labelText:
                                                                                                'B',
                                                                                          ),
                                                                                          onChanged: (
                                                                                            value,
                                                                                          ) {
                                                                                            final b =
                                                                                                int.tryParse(
                                                                                                  value,
                                                                                                ) ??
                                                                                                0;
                                                                                            tempColor = tempColor.withBlue(
                                                                                              b.clamp(
                                                                                                0,
                                                                                                255,
                                                                                              ),
                                                                                            );
                                                                                            updateControllers(
                                                                                              tempColor,
                                                                                            );
                                                                                            setState(
                                                                                              () {},
                                                                                            );
                                                                                            setStateDialog(
                                                                                              () {},
                                                                                            );
                                                                                          },
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                  ),
                                                                                  const SizedBox(
                                                                                    height:
                                                                                        16,
                                                                                  ),
                                                                                  Wrap(
                                                                                    spacing:
                                                                                        8,
                                                                                    runSpacing:
                                                                                        8,
                                                                                    children: [
                                                                                      ..._presetColors.map(
                                                                                        (
                                                                                          color,
                                                                                        ) => GestureDetector(
                                                                                          onTap: () {
                                                                                            setState(
                                                                                              () =>
                                                                                                  tempColor =
                                                                                                      color,
                                                                                            );
                                                                                            updateControllers(
                                                                                              color,
                                                                                            );
                                                                                            setStateDialog(
                                                                                              () {},
                                                                                            );
                                                                                          },
                                                                                          child: Container(
                                                                                            width:
                                                                                                30,
                                                                                            height:
                                                                                                30,
                                                                                            decoration: BoxDecoration(
                                                                                              color:
                                                                                                  color,
                                                                                              shape:
                                                                                                  BoxShape.circle,
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                            ),

                                                                            actions: [
                                                                              TextButton(
                                                                                onPressed:
                                                                                    () => Navigator.pop(
                                                                                      context,
                                                                                      null,
                                                                                    ),
                                                                                child: const Text(
                                                                                  '取消',
                                                                                ),
                                                                              ),
                                                                              ElevatedButton(
                                                                                onPressed:
                                                                                    () => Navigator.pop(
                                                                                      context,
                                                                                      tempColor,
                                                                                    ),
                                                                                child: const Text(
                                                                                  '確定',
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                    ),
                                                              );
                                                              if (picked !=
                                                                  null) {
                                                                setState(
                                                                  () =>
                                                                      selectedColor =
                                                                          picked,
                                                                ); // 🔥🔥🔥按確定後把 picked 更新回 selectedColor
                                                              }
                                                            },
                                                            child: const Text(
                                                              '選擇顏色',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed:
                                                          () => Navigator.pop(
                                                            context,
                                                          ),
                                                      child: const Text('取消'),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () {
                                                        if (nameController
                                                            .text
                                                            .isNotEmpty) {
                                                          Navigator.pop(context, {
                                                            'stage':
                                                                nameController
                                                                    .text,
                                                            'color':
                                                                '#${selectedColor.value.toRadixString(16).substring(2)}',
                                                            'performances':
                                                                stage['performances'] ??
                                                                {},
                                                          });
                                                        }
                                                      },
                                                      child: const Text('儲存'),
                                                    ),
                                                  ],
                                                ),
                                          ),
                                    );

                                    if (updatedStage != null) {
                                      setState(() {
                                        stages[index] =
                                            Map<String, dynamic>.from(
                                              updatedStage,
                                            );
                                      });
                                      widget.onUpdate({
                                        'id':
                                            widget.festival['id'], // ★★★ 一定要帶！
                                        'name': widget.festival['name'] ?? '',
                                        'start': widget.festival['start'] ?? '',
                                        'end': widget.festival['end'] ?? '',
                                        'stages': stages,
                                        'image': widget.festival['image'] ?? '',
                                      });
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                  ),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder:
                                          (_) => AlertDialog(
                                            title: const Text('確定刪除舞台？'),
                                            content: Text(
                                              '刪除「${stage['stage']}」將移除所有節目，是否確定？',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () => Navigator.pop(
                                                      context,
                                                      false,
                                                    ),
                                                child: const Text('取消'),
                                              ),
                                              ElevatedButton(
                                                onPressed:
                                                    () => Navigator.pop(
                                                      context,
                                                      true,
                                                    ),
                                                child: const Text('刪除'),
                                              ),
                                            ],
                                          ),
                                    );
                                    if (confirmed == true) {
                                      setState(() {
                                        stages.removeAt(index);
                                      });
                                      widget.onUpdate({
                                        'id':
                                            widget.festival['id'], // ★★★ 一定要帶！
                                        'name': widget.festival['name'] ?? '',
                                        'start': widget.festival['start'] ?? '',
                                        'end': widget.festival['end'] ?? '',
                                        'stages': stages,
                                        'image': widget.festival['image'] ?? '',
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),

                          children: [
                            ...List.generate(dayPerformances.length, (i) {
                              final p = dayPerformances[i];
                              return ListTile(
                                title: Text(p['band']),
                                subtitle: Text(p['time']),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.black54,
                                      ),
                                      onPressed: () async {
                                        final parts = (p['time'] as String)
                                            .split(' - ');
                                        TimeOfDay? start =
                                            parts.length == 2
                                                ? TimeOfDay(
                                                  hour: int.parse(
                                                    parts[0].split(':')[0],
                                                  ),
                                                  minute: int.parse(
                                                    parts[0].split(':')[1],
                                                  ),
                                                )
                                                : null;
                                        TimeOfDay? end =
                                            parts.length == 2
                                                ? TimeOfDay(
                                                  hour: int.parse(
                                                    parts[1].split(':')[0],
                                                  ),
                                                  minute: int.parse(
                                                    parts[1].split(':')[1],
                                                  ),
                                                )
                                                : null;
                                        final bandController =
                                            TextEditingController(
                                              text: p['band'],
                                            );

                                        final edited = await showDialog<
                                          Map<String, dynamic>
                                        >(
                                          context: context,
                                          builder:
                                              (_) => StatefulBuilder(
                                                builder:
                                                    (
                                                      context,
                                                      setState,
                                                    ) => AlertDialog(
                                                      title: const Text('編輯節目'),
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          TextField(
                                                            controller:
                                                                bandController,
                                                            decoration:
                                                                const InputDecoration(
                                                                  labelText:
                                                                      '樂團名稱',
                                                                ),
                                                          ),
                                                          Row(
                                                            children: [
                                                              const Text('開始'),
                                                              TextButton(
                                                                onPressed: () async {
                                                                  final picked = await showTimePicker(
                                                                    context:
                                                                        context,
                                                                    initialTime:
                                                                        start ??
                                                                        const TimeOfDay(
                                                                          hour:
                                                                              12,
                                                                          minute:
                                                                              0,
                                                                        ),
                                                                  );
                                                                  if (picked !=
                                                                      null) {
                                                                    setState(
                                                                      () =>
                                                                          start =
                                                                              picked,
                                                                    );
                                                                  }
                                                                },
                                                                child: Text(
                                                                  start == null
                                                                      ? '選擇時間'
                                                                      : '${start!.hour.toString().padLeft(2, '0')}:${start!.minute.toString().padLeft(2, '0')}',
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          Row(
                                                            children: [
                                                              const Text('結束'),
                                                              TextButton(
                                                                onPressed: () async {
                                                                  final picked = await showTimePicker(
                                                                    context:
                                                                        context,
                                                                    initialTime:
                                                                        end ??
                                                                        const TimeOfDay(
                                                                          hour:
                                                                              13,
                                                                          minute:
                                                                              0,
                                                                        ),
                                                                  );
                                                                  if (picked !=
                                                                      null) {
                                                                    setState(
                                                                      () =>
                                                                          end =
                                                                              picked,
                                                                    );
                                                                  }
                                                                },
                                                                child: Text(
                                                                  end == null
                                                                      ? '選擇時間'
                                                                      : '${end!.hour.toString().padLeft(2, '0')}:${end!.minute.toString().padLeft(2, '0')}',
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                  ),
                                                          child: const Text(
                                                            '取消',
                                                          ),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () {
                                                            if (bandController
                                                                    .text
                                                                    .isNotEmpty &&
                                                                start != null &&
                                                                end != null) {
                                                              Navigator.pop(
                                                                context,
                                                                {
                                                                  'band':
                                                                      bandController
                                                                          .text,
                                                                  'time':
                                                                      '${start!.hour.toString().padLeft(2, '0')}:${start!.minute.toString().padLeft(2, '0')} - ${end!.hour.toString().padLeft(2, '0')}:${end!.minute.toString().padLeft(2, '0')}',
                                                                },
                                                              );
                                                            }
                                                          },
                                                          child: const Text(
                                                            '確定',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                              ),
                                        );

                                        if (edited != null) {
                                          setState(() {
                                            dayPerformances[i] = edited;
                                            stage['performances'][dateKey] =
                                                dayPerformances;
                                          });
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.black54,
                                      ),
                                      onPressed: () async {
                                        final confirmed = await showDialog<
                                          bool
                                        >(
                                          context: context,
                                          builder:
                                              (_) => AlertDialog(
                                                title: const Text('確定刪除節目？'),
                                                content: Text(
                                                  '你確定要刪除「${p['band']}」這場演出嗎？',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed:
                                                        () => Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text('取消'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed:
                                                        () => Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    child: const Text('刪除'),
                                                  ),
                                                ],
                                              ),
                                        );

                                        if (confirmed == true) {
                                          setState(() {
                                            dayPerformances.removeAt(i);
                                            stage['performances'][dateKey] =
                                                dayPerformances;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }),

                            TextButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('新增演出'),
                              onPressed: () => _addPerformance(index, dateKey),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
