// Change 1: move ln swap fields from SwapTx to SwapTx.lnSwapDetails
import 'dart:convert';

import 'package:bb_mobile/_model/swap.dart';
import 'package:bb_mobile/_model/wallet.dart';
import 'package:bb_mobile/_pkg/storage/hive.dart';
import 'package:bb_mobile/_pkg/storage/secure_storage.dart';
import 'package:bb_mobile/_pkg/storage/storage.dart';
import 'package:bb_mobile/_pkg/wallet/repository/sensitive_storage.dart';
import 'package:boltz_dart/boltz_dart.dart';

Future<void> doMigration0_2to0_3(
  SecureStorage secureStorage,
  HiveStorage hiveStorage,
) async {
  print('Migration: 0.2 to 0.3');

  final (walletIds, walletIdsErr) =
      await hiveStorage.getValue(StorageKeys.wallets);
  if (walletIdsErr != null) throw walletIdsErr;

  final walletIdsJson = jsonDecode(walletIds!)['wallets'] as List<dynamic>;
  if (walletIdsJson.isEmpty) throw 'No Wallets found';

  final WalletSensitiveStorageRepository walletSensitiveStorageRepository =
      WalletSensitiveStorageRepository(secureStorage: secureStorage);

  final List<Wallet> wallets = [];

  for (final walletId in walletIdsJson) {
    // print('walletId: $walletId');
    final (jsn, err) = await hiveStorage.getValue(walletId as String);
    if (err != null) throw err;

    final Map<String, dynamic> walletObj =
        jsonDecode(jsn!) as Map<String, dynamic>;

    final updatedWalletObj =
        await updateSwaps(walletObj, walletSensitiveStorageRepository);

    final w = Wallet.fromJson(updatedWalletObj);
    wallets.add(w);
  }

  final walletObjs = wallets.map((w) => w.toJson()).toList();
  final List<String> ids = [];
  for (final w in walletObjs) {
    final id = w['id'] as String;
    ids.add(id);
    final _ = await hiveStorage.saveValue(
      key: id,
      value: jsonEncode(w),
    );
  }

  final idsJsn = jsonEncode({
    'wallets': [...ids],
  });
  final _ = await hiveStorage.saveValue(
    key: StorageKeys.wallets,
    value: idsJsn,
  );

  // Finally update version number to next version
  // why arent we using toVersion and hardcoding 0.2 here?
  await secureStorage.saveValue(key: StorageKeys.version, value: '0.3');
}

Future<Map<String, dynamic>> updateSwaps(
  Map<String, dynamic> walletObj,
  WalletSensitiveStorageRepository walletSensitiveStorageRepository,
) async {
  walletObj['transactions'] = walletObj['transactions']
      .map((tx) => tx as Map<String, dynamic>)
      .map((tx) {
    final txHasSwap = tx['swapTx'] != null;
    final swapTxHasInvoice = txHasSwap && tx['swapTx']['invoice'] != null;
    if (swapTxHasInvoice) {
      final isSubmarine = tx['swapTx']['isSubmarine'] == true;
      if (isSubmarine)
        tx['swapTx']['lockupTxid'] = tx['swapTx']['txid'];
      else
        tx['swapTx']['claimTxid'] = tx['swapTx']['txid'];

      tx['swapTx']['lnSwapDetails'] = LnSwapDetails(
        swapType: isSubmarine ? SwapType.submarine : SwapType.reverse,
        invoice: tx['swapTx']['invoice'] as String,
        boltzPubKey: tx['swapTx']['boltzPubkey'] as String,
        keyIndex: tx['swapTx']['keyIndex'] != null
            ? tx['swapTx']['keyIndex'] as int
            : 0,
        myPublicKey: tx['swapTx']['publicKey'] as String,
        electrumUrl: tx['swapTx']['electrumUrl'] as String,
        locktime: tx['swapTx']['locktime'] as int,
        sha256: tx['swapTx']['sha256'] != null
            ? tx['swapTx']['sha256'] as String
            : '',
        hash160: tx['swapTx']['hash160'] != null
            ? tx['swapTx']['hash160'] as String
            : '',
        blindingKey: tx['swapTx']['blindingKey'] != null
            ? tx['swapTx']['blindingKey'] as String
            : '',
      ).toJson();
      return tx;
    }
    return tx;
  }).toList();

  return walletObj;
}
