import 'package:RatNawnAI_app/features/export/bloc/export_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../upload/bloc/upload_bloc.dart';


class FashionAIScreen extends StatefulWidget {
  const FashionAIScreen({super.key});

  @override
  State<FashionAIScreen> createState() => _FashionAIScreenState();
}

class _FashionAIScreenState extends State<FashionAIScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _productController = TextEditingController();


  @override
  void initState() {
    super.initState();
    // Set default values
    _usernameController.text = 'test_user';
    _productController.text = 'Fashion Item';
    _textController.text = 'Create a professional fashion model photo showing this clothing item in an elegant studio setting with good lighting';
  }

  @override
  void dispose() {
    _textController.dispose();
    _usernameController.dispose();
    _productController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fashion AI Generator'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: MultiBlocListener(
        listeners: [
          BlocListener<UploadBloc, UploadState>(
            listener: (context, state) {
              if (state is FashionGenerationSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Fashion report generated successfully!'),
                    backgroundColor: Colors.blue,
                  ),
                );
                
                // Auto-export Excel file if available
                if (state.response.excelReportUrl != null) {
                  final fileName = 'fashion_report_${state.response.requestId}.xlsx';
                  context.read<exportBloc>().add(
                    exportExcelFile(
                      url: state.response.excelReportUrl!,
                      fileName: fileName,
                    ),
                  );
                }
              } else if (state is FashionGenerationError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Error: ${state.message}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
          BlocListener<exportBloc, exportState>(
            listener: (context, state) {
              if (state is ExcelexportSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('📄 Excel file exported: ${state.fileName}'),
                    backgroundColor: Colors.blue,
                    action: SnackBarAction(
                      label: 'View',
                      onPressed: () {
                        _showFileLocationDialog(state.filePath);
                      },
                    ),
                  ),
                );
              } else if (state is exportError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ export Error: ${state.message}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ],
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImageSection(),
              const SizedBox(height: 24),
              _buildInputSection(),
              const SizedBox(height: 24),
              _buildActionButtons(),
              const SizedBox(height: 24),
              _buildStatusSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Images',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select fashion item images (frontside required, others optional)',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            BlocBuilder<UploadBloc, UploadState>(
              builder: (context, state) {
                if (state is ImagesSelected) {
                  return Column(
                    children: [
                      _buildImageGrid(state.images),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _selectImages(),
                              icon: const Icon(Icons.add_photo_alternate),
                              label: const Text('Add More Images'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => context.read<UploadBloc>().add(const ClearImages()),
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[100],
                              foregroundColor: Colors.red[800],
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }
                
                return ElevatedButton.icon(
                  onPressed: () => _selectImages(),
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Select Images'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid(List<XFile> images) {
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        itemBuilder: (context, index) {
          final image = images[index];
          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(image.path),
                    width: 100,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 16),
                      onPressed: () => context.read<UploadBloc>().add(RemoveImage(index: index)),
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getImageLabel(index),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _getImageLabel(int index) {
    switch (index) {
      case 0: return 'Front';
      case 1: return 'Back';
      case 2: return 'Side';
      case 3: return 'Detail';
      default: return 'Extra';
    }
  }

  Widget _buildInputSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Generation Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _productController,
              decoration: const InputDecoration(
                labelText: 'Product Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description/Instructions',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
                hintText: 'Describe how you want the fashion item to be presented...',
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return BlocBuilder<UploadBloc, UploadState>(
      builder: (context, state) {
        final isGenerating = state is FashionGenerationInProgress;
        final hasImages = state is ImagesSelected && state.images.isNotEmpty;
        
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: hasImages && !isGenerating ? _generateFashionReport : null,
                icon: isGenerating 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(isGenerating ? 'Generating...' : 'Generate Fashion Report'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (!hasImages) ...[
              const SizedBox(height: 8),
              const Text(
                'Please select at least one image to continue',
                style: TextStyle(color: Colors.orange),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStatusSection() {
    return BlocBuilder<UploadBloc, UploadState>(
      builder: (context, uploadState) {
        return BlocBuilder<exportBloc, exportState>(
          builder: (context, exportState) {
            if (uploadState is FashionGenerationInProgress) {
              return Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(uploadState.message),
                    ],
                  ),
                ),
              );
            }
            
            if (uploadState is FashionGenerationSuccess) {
              return Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '✅ Generation Complete',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Request ID: ${uploadState.response.requestId}'),
                      if (uploadState.response.outputImageUrl != null) ...[
                        const SizedBox(height: 4),
                        Text('Output Image: Available'),
                      ],
                      if (uploadState.response.outputVideoUrl != null) ...[
                        const SizedBox(height: 4),
                        Text('Video: Available'),
                      ],
                      if (uploadState.response.excelReportUrl != null) ...[
                        const SizedBox(height: 4),
                        Text('Excel Report: Available'),
                      ],
                    ],
                  ),
                ),
              );
            }
            
            if (exportState is ExcelexportInProgress) {
              return Card(
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: exportState.progress),
                      const SizedBox(height: 8),
                      Text('exporting ${exportState.fileName}...'),
                      Text('${(exportState.progress * 100).toStringAsFixed(1)}%'),
                    ],
                  ),
                ),
              );
            }
            
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  void _selectImages() {
    context.read<UploadBloc>().add(const SelectImages());
  }

  void _generateFashionReport() {
    if (_textController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a description'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    if (_usernameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a username'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    if (_productController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a product name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    context.read<UploadBloc>().add(
      GenerateFashionReport(
        text: _textController.text,
        username: _usernameController.text,
        product: _productController.text,

      ),
    );
  }

  void _showFileLocationDialog(String filePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File exported'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Excel file has been saved to:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                filePath,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
} 