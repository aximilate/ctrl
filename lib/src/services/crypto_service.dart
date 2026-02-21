import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class CryptoRegistrationPayload {
  const CryptoRegistrationPayload({
    required this.identityPublicKey,
    required this.signedPrekeyPublic,
    required this.signedPrekeySignature,
    required this.oneTimePrekeys,
    required this.identityPrivateKey,
    required this.signedPrekeyPrivate,
  });

  final String identityPublicKey;
  final String signedPrekeyPublic;
  final String signedPrekeySignature;
  final List<String> oneTimePrekeys;
  final String identityPrivateKey;
  final String signedPrekeyPrivate;
}

class EncryptedPayload {
  const EncryptedPayload({
    required this.counter,
    required this.nonce,
    required this.mac,
    required this.ciphertext,
  });

  final int counter;
  final String nonce;
  final String mac;
  final String ciphertext;

  String toJsonString() {
    return jsonEncode({
      'counter': counter,
      'nonce': nonce,
      'mac': mac,
      'ciphertext': ciphertext,
    });
  }

  factory EncryptedPayload.fromJsonString(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return EncryptedPayload(
      counter: (json['counter'] ?? 0) as int,
      nonce: (json['nonce'] ?? '') as String,
      mac: (json['mac'] ?? '') as String,
      ciphertext: (json['ciphertext'] ?? '') as String,
    );
  }
}

class CryptoService {
  final _x25519 = X25519();
  final _ed25519 = Ed25519();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final _rng = Random.secure();

  Future<CryptoRegistrationPayload> createRegistrationPayload() async {
    final identityPair = await _x25519.newKeyPair();
    final identityPublic = await identityPair.extractPublicKey();
    final identityPrivate = await identityPair.extractPrivateKeyBytes();

    final signedPrekeyPair = await _x25519.newKeyPair();
    final signedPrekeyPublic = await signedPrekeyPair.extractPublicKey();
    final signedPrekeyPrivate = await signedPrekeyPair.extractPrivateKeyBytes();

    final signatureKeyPair = await _ed25519.newKeyPair();
    final signed = await _ed25519.sign(
      signedPrekeyPublic.bytes,
      keyPair: signatureKeyPair,
    );

    final oneTimePrekeys = <String>[];
    for (var i = 0; i < 25; i += 1) {
      final keyPair = await _x25519.newKeyPair();
      final key = await keyPair.extractPublicKey();
      oneTimePrekeys.add(base64Encode(key.bytes));
    }

    return CryptoRegistrationPayload(
      identityPublicKey: base64Encode(identityPublic.bytes),
      signedPrekeyPublic: base64Encode(signedPrekeyPublic.bytes),
      signedPrekeySignature: base64Encode(signed.bytes),
      oneTimePrekeys: oneTimePrekeys,
      identityPrivateKey: base64Encode(identityPrivate),
      signedPrekeyPrivate: base64Encode(signedPrekeyPrivate),
    );
  }

  Future<SecretKey> deriveSharedSecret({
    required String privateKeyBase64,
    required String publicKeyBase64,
  }) async {
    final privateBytes = base64Decode(privateKeyBase64);
    final publicBytes = base64Decode(publicKeyBase64);
    final keyPairData = await _x25519.newKeyPairFromSeed(privateBytes);
    final remotePublic = SimplePublicKey(publicBytes, type: KeyPairType.x25519);
    return _x25519.sharedSecretKey(
      keyPair: keyPairData,
      remotePublicKey: remotePublic,
    );
  }

  Future<EncryptedPayload> encryptMessage({
    required SecretKey sharedSecret,
    required String plaintext,
    required int counter,
  }) async {
    final messageKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('ctrlchat-msg-$counter'),
      info: utf8.encode('x3dh-double-ratchet-chain'),
    );
    final nonceBytes = Uint8List.fromList(
      List<int>.generate(24, (_) => _rng.nextInt(256)),
    );
    final box = await Xchacha20.poly1305Aead().encrypt(
      utf8.encode(plaintext),
      secretKey: messageKey,
      nonce: nonceBytes,
    );
    return EncryptedPayload(
      counter: counter,
      nonce: base64Encode(box.nonce),
      mac: base64Encode(box.mac.bytes),
      ciphertext: base64Encode(box.cipherText),
    );
  }

  Future<String> decryptMessage({
    required SecretKey sharedSecret,
    required EncryptedPayload payload,
  }) async {
    final messageKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('ctrlchat-msg-${payload.counter}'),
      info: utf8.encode('x3dh-double-ratchet-chain'),
    );
    final clear = await Xchacha20.poly1305Aead().decrypt(
      SecretBox(
        base64Decode(payload.ciphertext),
        nonce: base64Decode(payload.nonce),
        mac: Mac(base64Decode(payload.mac)),
      ),
      secretKey: messageKey,
    );
    return utf8.decode(clear);
  }
}
