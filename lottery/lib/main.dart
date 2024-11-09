// lib/main.dart
import 'package:flutter/material.dart';
import 'package:aptos_sdk_dart/aptos_sdk_dart.dart';
import 'package:file_picker/file_picker.dart';
//import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  runApp(const FileShareApp());
}

class FileShareApp extends StatelessWidget {
  const FileShareApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aptos File Sharing',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AptosClient client = AptosClient('https://fullnode.devnet.aptoslabs.com');
  final storage = const FlutterSecureStorage();
  String? walletAddress;
  List<FileInfo> files = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeWallet();
  }

  Future<void> _initializeWallet() async {
    try {
      final privateKey = await storage.read(key: 'private_key');
      if (privateKey == null) {
        final account = AptosAccount();
        await storage.write(key: 'private_key', value: account.privateKey);
        setState(() {
          walletAddress = account.address;
        });
      } else {
        final account = AptosAccount.fromPrivateKey(privateKey);
        setState(() {
          walletAddress = account.address;
        });
      }
      _loadFiles();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error initializing wallet: $e')),
      );
    }
  }

  Future<void> _uploadFile() async {
    try {
      setState(() => isLoading = true);
      
      final result = await FilePicker.platform.pickFiles();
      if (result == null) return;

      final file = result.files.first;
      final bytes = file.bytes!;
      final hash = sha256.convert(bytes).toString();
      
      final account = AptosAccount.fromPrivateKey(
        await storage.read(key: 'private_key') ?? '',
      );

      final transaction = await client.generateTransaction(
        account.address,
        EntryFunction.natural(
          'file_sharing_addr::file_sharing',
          'upload_file',
          [],
          [hash, file.name],
        ),
      );

      final signedTxn = await client.signTransaction(account, transaction);
      final response = await client.submitTransaction(signedTxn);
      await client.waitForTransaction(response.hash);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File uploaded successfully!')),
      );
      _loadFiles();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading file: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadFiles() async {
    try {
      setState(() => isLoading = true);
      
      final resources = await client.getAccountResources(walletAddress!);
      final storageResource = resources.firstWhere(
        (r) => r.type == 'file_sharing_addr::file_sharing::FileStorage',
      );

      setState(() {
        files = (storageResource.data['files'] as List)
            .map((f) => FileInfo.fromJson(f))
            .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading files: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aptos File Sharing'),
        actions: [
          if (walletAddress != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: Text(
                  'Wallet: ${walletAddress!.substring(0, 6)}...${walletAddress!.substring(walletAddress!.length - 4)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : files.isEmpty
              ? const Center(child: Text('No files uploaded yet'))
              : ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      leading: const Icon(Icons.file_present),
                      title: Text(file.fileName),
                      subtitle: Text('Hash: ${file.fileHash.substring(0, 10)}...'),
                      trailing: IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () => _showShareDialog(file),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploadFile,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showShareDialog(FileInfo file) async {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Enter recipient address',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final account = AptosAccount.fromPrivateKey(
                  await storage.read(key: 'private_key') ?? '',
                );

                final transaction = await client.generateTransaction(
                  account.address,
                  EntryFunction.natural(
                    'file_sharing_addr::file_sharing',
                    'share_file',
                    [],
                    [file.fileHash, controller.text],
                  ),
                );

                final signedTxn = await client.signTransaction(account, transaction);
                final response = await client.submitTransaction(signedTxn);
                await client.waitForTransaction(response.hash);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File shared successfully!')),
                );
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error sharing file: $e')),
                );
              }
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }
}

class FileInfo {
  final String fileHash;
  final String fileName;
  final String owner;
  final List<String> sharedWith;
  final int timestamp;

  FileInfo({
    required this.fileHash,
    required this.fileName,
    required this.owner,
    required this.sharedWith,
    required this.timestamp,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      fileHash: json['file_hash'],
      fileName: json['file_name'],
      owner: json['owner'],
      sharedWith: List<String>.from(json['shared_with']),
      timestamp: json['timestamp'],
    );
  }
}